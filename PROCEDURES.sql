-- ============================================================
--  STORED PROCEDURES — ASILO SALUD MENTAL
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  Ejecutar despues de DDL.sql
--  REGLA: Solo CREATE PROCEDURE (nunca CREATE FUNCTION salvo
--         trigger handlers que requieren RETURNS trigger).
-- ============================================================


-- ============================================================
-- AUDITORIA
-- ============================================================

-- Registra una entrada en el log de auditoria.
-- Llamar desde Python despues de cualquier INSERT/UPDATE/DELETE sensible.
CREATE OR REPLACE PROCEDURE sp_registrar_auditoria(
    p_id_usuario    INT,
    p_tabla         VARCHAR,
    p_operacion     VARCHAR,
    p_id_registro   INT,
    p_ip            VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro, ip_origen)
    VALUES (p_id_usuario, p_tabla, p_operacion, p_id_registro, p_ip);
END;
$$;


-- ============================================================
-- RESIDENTES
-- ============================================================

-- Alta de nuevo residente con asignacion inicial de cuidador.
-- OUT ok: 1=exito, 0=error. OUT msg: descripcion del resultado.
CREATE OR REPLACE PROCEDURE sp_registrar_residente(
    p_nombre            VARCHAR,
    p_apellidos         VARCHAR,
    p_fecha_nacimiento  DATE,
    p_sexo              CHAR,
    p_habitacion        VARCHAR,
    p_diagnostico       TEXT,
    p_nivel_movilidad   VARCHAR,
    p_contacto          VARCHAR,
    p_tel_contacto      VARCHAR,
    p_id_cuidador       INT,        -- staff que se asignara como cuidador principal
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_residente  INT;
    v_edad          INT;
    v_fecha_max     DATE;
BEGIN
    -- Validar edad minima de 65 años
    v_edad      := EXTRACT(YEAR FROM AGE(p_fecha_nacimiento))::INT;
    v_fecha_max := CURRENT_DATE - INTERVAL '65 years';

    IF p_fecha_nacimiento > v_fecha_max THEN
        ok  := 0;
        msg := 'El residente debe tener al menos 65 años para ingresar al asilo. '
            || 'Edad ingresada: ' || v_edad || ' años. '
            || 'La fecha de nacimiento no puede ser posterior al '
            || TO_CHAR(v_fecha_max, 'DD/MM/YYYY') || '.';
        RETURN;
    END IF;

    -- Validar que la habitacion no este ocupada por otro residente activo
    IF p_habitacion IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM residente
            WHERE habitacion = p_habitacion AND activo = TRUE
        ) THEN
            ok  := 0;
            msg := 'La habitacion ' || p_habitacion || ' ya esta ocupada por otro residente activo. '
                || 'Asigne una habitacion diferente o deje el campo vacio.';
            RETURN;
        END IF;
    END IF;

    -- Insertar residente
    INSERT INTO residente (nombre, apellidos, fecha_nacimiento, sexo, habitacion,
                           diagnostico_principal, nivel_movilidad,
                           contacto_emergencia, tel_emergencia)
    VALUES (p_nombre, p_apellidos, p_fecha_nacimiento, p_sexo, p_habitacion,
            p_diagnostico, p_nivel_movilidad, p_contacto, p_tel_contacto)
    RETURNING id_residente INTO v_id_residente;

    -- Asignacion inicial
    IF p_id_cuidador IS NOT NULL THEN
        INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal)
        VALUES (v_id_residente, p_id_cuidador, 'Cuidador', TRUE);
    END IF;

    ok  := 1;
    msg := 'Residente registrado con ID ' || v_id_residente;
EXCEPTION WHEN OTHERS THEN
    ok  := 0;
    msg := 'Error al registrar el residente: ' || SQLERRM;
END;
$$;


-- Baja logica de residente (no elimina datos historicos).
CREATE OR REPLACE PROCEDURE sp_dar_baja_residente(
    p_id_residente  INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE residente SET activo = FALSE WHERE id_residente = p_id_residente;
    IF NOT FOUND THEN
        ok := 0; msg := 'Residente no encontrado.';
    ELSE
        -- Cerrar asignaciones activas
        UPDATE asignacion SET fecha_fin = CURRENT_DATE
        WHERE id_residente = p_id_residente AND fecha_fin IS NULL;
        ok := 1; msg := 'Residente dado de baja correctamente.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualizar datos basicos del residente.
CREATE OR REPLACE PROCEDURE sp_actualizar_residente(
    p_id_residente      INT,
    p_habitacion        VARCHAR,
    p_diagnostico       TEXT,
    p_nivel_movilidad   VARCHAR,
    p_contacto          VARCHAR,
    p_tel_contacto      VARCHAR,
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Validar que la habitacion no este ocupada por otro residente activo distinto
    IF p_habitacion IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM residente
            WHERE habitacion = p_habitacion
              AND activo     = TRUE
              AND id_residente <> p_id_residente
        ) THEN
            ok  := 0;
            msg := 'La habitacion ' || p_habitacion || ' ya esta ocupada por otro residente activo. '
                || 'Asigne una habitacion diferente o deje el campo vacio.';
            RETURN;
        END IF;
    END IF;

    UPDATE residente
    SET habitacion            = p_habitacion,
        diagnostico_principal = p_diagnostico,
        nivel_movilidad       = p_nivel_movilidad,
        contacto_emergencia   = p_contacto,
        tel_emergencia        = p_tel_contacto
    WHERE id_residente = p_id_residente AND activo = TRUE;

    IF NOT FOUND THEN
        ok := 0; msg := 'Residente no encontrado o inactivo.';
    ELSE
        ok := 1; msg := 'Residente actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error al actualizar el residente: ' || SQLERRM;
END;
$$;


-- ============================================================
-- SESIONES DE TERAPIA
-- ============================================================

-- Reservar sesion con deteccion de conflicto de horario.
-- Verifica que el terapeuta y la sala esten libres en ese bloque.
CREATE OR REPLACE PROCEDURE sp_reservar_sesion(
    p_id_residente  INT,
    p_id_terapeuta  INT,
    p_id_sala       INT,
    p_fecha_sesion  TIMESTAMP,
    p_duracion_min  INT,
    p_tipo_sesion   VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_fin           TIMESTAMP;
    v_conflicto_t   INT := 0;
    v_conflicto_s   INT := 0;
BEGIN
    v_fin := p_fecha_sesion + (p_duracion_min || ' minutes')::INTERVAL;

    -- Conflicto de terapeuta
    SELECT COUNT(*) INTO v_conflicto_t
    FROM sesion_terapia
    WHERE id_terapeuta = p_id_terapeuta
      AND fecha_sesion < v_fin
      AND (fecha_sesion + (duracion_min || ' minutes')::INTERVAL) > p_fecha_sesion;

    -- Conflicto de sala
    SELECT COUNT(*) INTO v_conflicto_s
    FROM sesion_terapia
    WHERE id_sala = p_id_sala
      AND fecha_sesion < v_fin
      AND (fecha_sesion + (duracion_min || ' minutes')::INTERVAL) > p_fecha_sesion;

    IF v_conflicto_t > 0 THEN
        ok := 0; msg := 'El terapeuta ya tiene una sesion en ese horario.';
        RETURN;
    END IF;

    IF v_conflicto_s > 0 THEN
        ok := 0; msg := 'La sala ya esta ocupada en ese horario.';
        RETURN;
    END IF;

    INSERT INTO sesion_terapia (id_residente, id_terapeuta, id_sala,
                                fecha_sesion, tipo_sesion, duracion_min)
    VALUES (p_id_residente, p_id_terapeuta, p_id_sala,
            p_fecha_sesion, p_tipo_sesion, p_duracion_min);

    ok := 1; msg := 'Sesion registrada correctamente.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualizar notas y asistencia de una sesion.
CREATE OR REPLACE PROCEDURE sp_actualizar_sesion(
    p_id_sesion INT,
    p_asistio   BOOLEAN,
    p_notas     TEXT,
    OUT ok      INT,
    OUT msg     TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sesion_terapia
    SET asistio = p_asistio, notas = p_notas
    WHERE id_sesion = p_id_sesion;

    IF NOT FOUND THEN
        ok := 0; msg := 'Sesion no encontrada.';
    ELSE
        ok := 1; msg := 'Sesion actualizada.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- MEDICAMENTOS — NFC
-- ============================================================

-- Registra administracion de medicamento via escaneo NFC.
-- Flujo: NFC tag → identifica residente → busca horario activo
--        → inserta nfc_evento + log_medicamento (transaccion).
CREATE OR REPLACE PROCEDURE sp_log_medicamento_nfc(
    p_codigo_tag    VARCHAR,
    p_id_staff      INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_tag        INT;
    v_id_residente  INT;
    v_id_horario    INT;
    v_id_log        BIGINT;
    v_id_evento     BIGINT;
BEGIN
    -- Buscar el tag
    SELECT id_tag, id_residente INTO v_id_tag, v_id_residente
    FROM nfc_tag
    WHERE codigo_tag = p_codigo_tag;

    IF NOT FOUND THEN
        ok := 0; msg := 'Tag NFC no registrado.';
        RETURN;
    END IF;

    -- Buscar horario activo mas cercano a la hora actual (±2 horas)
    SELECT id_horario INTO v_id_horario
    FROM horario_medicamento
    WHERE id_residente = v_id_residente
      AND activo = TRUE
      AND hora_programada BETWEEN (CURRENT_TIME - INTERVAL '2 hours')
                               AND (CURRENT_TIME + INTERVAL '2 hours')
    ORDER BY ABS(EXTRACT(EPOCH FROM (hora_programada - CURRENT_TIME)))
    LIMIT 1;

    IF NOT FOUND THEN
        ok := 0; msg := 'No se encontro horario de medicamento activo para esta hora.';
        RETURN;
    END IF;

    -- Registrar administracion primero para obtener id_log
    INSERT INTO log_medicamento (id_horario, id_cuidador)
    VALUES (v_id_horario, p_id_staff)
    RETURNING id_log INTO v_id_log;

    -- Registrar evento NFC con referencia al log
    INSERT INTO nfc_evento (id_tag, id_staff, id_log_med)
    VALUES (v_id_tag, p_id_staff, v_id_log)
    RETURNING id_evento INTO v_id_evento;

    ok := 1;
    msg := 'Medicamento registrado para residente ID ' || v_id_residente;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- IoT — GPS: ESTADO DE RESIDENTES EN EXTERIOR
-- ============================================================

-- Devuelve el ultimo ping GPS de cada residente y si esta
-- dentro del limite del jardin. Usa refcursor para retornar filas.
CREATE OR REPLACE PROCEDURE sp_residentes_al_aire_libre(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        r.id_residente,
        r.nombre || ' ' || r.apellidos       AS residente,
        r.habitacion,
        g.latitud,
        g.longitud,
        g.registrado_en,
        (g.latitud  BETWEEN lj.lat_min AND lj.lat_max
         AND g.longitud BETWEEN lj.lon_min AND lj.lon_max) AS dentro_limite,
        EXTRACT(EPOCH FROM (NOW() - g.registrado_en)) / 60 AS minutos_desde_ping
    FROM residente r
    JOIN LATERAL (
        SELECT latitud, longitud, registrado_en
        FROM gps_ping
        WHERE id_residente = r.id_residente
        ORDER BY registrado_en DESC
        LIMIT 1
    ) g ON TRUE
    CROSS JOIN limite_jardin lj
    WHERE r.activo = TRUE
    ORDER BY dentro_limite ASC, minutos_desde_ping ASC;
END;
$$;


-- ============================================================
-- IoT — RFID: LOG DE ACCESOS
-- ============================================================

-- Registra un evento de acceso RFID.
CREATE OR REPLACE PROCEDURE sp_registrar_acceso_rfid(
    p_id_lector         INT,
    p_id_staff          INT,
    p_acceso_concedido  BOOLEAN,
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO acceso_rfid (id_lector, id_staff, acceso_concedido)
    VALUES (p_id_lector, p_id_staff, COALESCE(p_acceso_concedido, TRUE));
    ok := 1; msg := 'Acceso registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Devuelve el log de accesos RFID para una fecha dada.
CREATE OR REPLACE PROCEDURE sp_log_acceso_rfid(
    p_fecha     DATE,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        ar.id_acceso,
        s.nombre || ' ' || s.apellidos  AS staff,
        s.especialidad,
        lr.ubicacion,
        a.nombre                         AS ala,
        lr.es_restringido,
        ar.acceso_concedido,
        TO_CHAR(ar.accedido_en, 'HH12:MI AM') AS hora
    FROM acceso_rfid ar
    JOIN staff      s  ON ar.id_staff  = s.id_staff
    JOIN lector_rfid lr ON ar.id_lector = lr.id_lector
    LEFT JOIN ala   a  ON lr.id_ala    = a.id_ala
    WHERE ar.accedido_en::DATE = p_fecha
    ORDER BY ar.accedido_en DESC;
END;
$$;


-- Detecta accesos a areas restringidas por staff sin turno asignado
-- en ese ala en esa fecha.
CREATE OR REPLACE PROCEDURE sp_accesos_no_autorizados(
    p_fecha DATE,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        ar.id_acceso,
        s.nombre || ' ' || s.apellidos  AS staff,
        s.especialidad,
        r.nombre_rol                     AS rol,
        lr.ubicacion,
        lr.ubicacion                     AS lector,
        a.nombre                         AS ala,
        TO_CHAR(ar.accedido_en, 'HH12:MI AM') AS hora
    FROM acceso_rfid ar
    JOIN staff       s   ON ar.id_staff   = s.id_staff
    JOIN rol         r   ON s.id_rol      = r.id_rol
    JOIN lector_rfid lr  ON ar.id_lector  = lr.id_lector
    LEFT JOIN ala    a   ON lr.id_ala     = a.id_ala
    WHERE ar.accedido_en::DATE = p_fecha
      AND lr.es_restringido = TRUE
      AND ar.acceso_concedido = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM turno t
          WHERE t.id_staff = ar.id_staff
            AND t.fecha    = p_fecha
            AND t.id_ala   = lr.id_ala
      )
    ORDER BY ar.accedido_en DESC;
END;
$$;


-- ============================================================
-- IoT — BEACON: UBICACION ACTUAL DEL STAFF
-- ============================================================

-- Devuelve la ultima deteccion beacon de cada miembro del staff
-- en turno hoy, indicando en que ala se encontraba.
CREATE OR REPLACE PROCEDURE sp_ubicacion_actual_staff(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.id_staff,
        s.nombre || ' ' || s.apellidos  AS staff,
        s.especialidad,
        r.nombre_rol                     AS rol,
        a.nombre                         AS ala_detectada,
        db.detectado_en,
        EXTRACT(EPOCH FROM (NOW() - db.detectado_en)) / 60 AS minutos_desde_deteccion
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    JOIN turno t ON t.id_staff = s.id_staff AND t.fecha = CURRENT_DATE
    LEFT JOIN LATERAL (
        SELECT db2.detectado_en, b.id_ala
        FROM deteccion_beacon db2
        JOIN beacon b ON db2.id_beacon = b.id_beacon
        WHERE db2.id_staff = s.id_staff
        ORDER BY db2.detectado_en DESC
        LIMIT 1
    ) db ON TRUE
    LEFT JOIN ala a ON db.id_ala = a.id_ala
    WHERE s.activo = TRUE
    ORDER BY a.nombre, s.apellidos;
END;
$$;


-- ============================================================
-- REPORTES
-- ============================================================

-- Reporte semanal por cuidador: residentes, check-ins, animo, meds, incidentes, dosis perdidas.
CREATE OR REPLACE PROCEDURE sp_resumen_semanal_cuidador(
    p_semana_inicio DATE,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.id_staff,
        s.nombre || ' ' || s.apellidos      AS cuidador,
        p_semana_inicio                      AS semana_inicio,
        p_semana_inicio + 6                  AS semana_fin,
        (SELECT COUNT(DISTINCT a2.id_residente)
         FROM asignacion a2
         WHERE a2.id_staff  = s.id_staff
           AND a2.tipo_rol  = 'Cuidador'
           AND (a2.fecha_fin IS NULL OR a2.fecha_fin >= p_semana_inicio)
        )                                    AS residentes_atendidos,
        COUNT(DISTINCT c.id_checkin)         AS total_checkins,
        ROUND(AVG(c.puntaje), 2)             AS puntaje_animo_promedio,
        COUNT(DISTINCT lm.id_log)            AS meds_administrados,
        (SELECT COUNT(*)
         FROM reporte_incidente ri
         WHERE ri.id_staff = s.id_staff
           AND ri.fecha::DATE BETWEEN p_semana_inicio AND p_semana_inicio + 6
        )                                    AS incidentes_reportados,
        (
            SELECT COUNT(*)
            FROM horario_medicamento hm
            JOIN asignacion a3 ON hm.id_residente = a3.id_residente
            WHERE a3.id_staff = s.id_staff
              AND a3.tipo_rol = 'Cuidador'
              AND hm.activo = TRUE
              AND NOT EXISTS (
                  SELECT 1 FROM log_medicamento lm2
                  WHERE lm2.id_horario = hm.id_horario
                    AND lm2.fecha_administracion::DATE
                        BETWEEN p_semana_inicio AND p_semana_inicio + 6
              )
        ) AS dosis_perdidas
    FROM staff s
    LEFT JOIN checkin_estado_animo c
           ON c.id_cuidador = s.id_staff
          AND c.fecha_registro::DATE BETWEEN p_semana_inicio AND p_semana_inicio + 6
    LEFT JOIN log_medicamento lm
           ON lm.id_cuidador = s.id_staff
          AND lm.fecha_administracion::DATE BETWEEN p_semana_inicio AND p_semana_inicio + 6
    JOIN rol r ON s.id_rol = r.id_rol AND r.nivel_acceso = 3
    WHERE s.activo = TRUE
    GROUP BY s.id_staff, s.nombre, s.apellidos
    ORDER BY puntaje_animo_promedio ASC NULLS LAST;
END;
$$;


-- Evolucion de estado de animo de un residente (para grafica de linea).
CREATE OR REPLACE PROCEDURE sp_evolucion_animo_residente(
    p_id_residente  INT,
    p_dias          INT,   -- ultimos N dias
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        DATE(fecha_registro)             AS fecha,
        ROUND(AVG(puntaje), 2)          AS puntaje_promedio,
        COUNT(*)                         AS num_registros
    FROM checkin_estado_animo
    WHERE id_residente = p_id_residente
      AND fecha_registro >= NOW() - (p_dias || ' days')::INTERVAL
    GROUP BY DATE(fecha_registro)
    ORDER BY fecha;
END;
$$;


-- ============================================================
-- TRIGGERS DE AUDITORIA
-- (unica excepcion permitida para CREATE FUNCTION)
-- ============================================================

-- Trigger handler para log_auditoria en tabla residente.
-- Se activa en UPDATE y DELETE sobre residente.
CREATE OR REPLACE FUNCTION trg_auditoria_residente()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id_usuario INT;
BEGIN
    -- El id de usuario se pasa via configuracion de sesion: SET LOCAL app.id_usuario = X
    BEGIN
        v_id_usuario := current_setting('app.id_usuario')::INT;
    EXCEPTION WHEN OTHERS THEN
        v_id_usuario := 0;  -- fallback si no esta seteado
    END;

    IF TG_OP = 'DELETE' THEN
        INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
        VALUES (v_id_usuario, 'residente', 'DELETE', OLD.id_residente);
    ELSE
        INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
        VALUES (v_id_usuario, 'residente', 'UPDATE', NEW.id_residente);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_residente ON residente;
CREATE TRIGGER trg_after_residente
AFTER UPDATE OR DELETE ON residente
FOR EACH ROW EXECUTE FUNCTION trg_auditoria_residente();


-- ============================================================
-- STAFF
-- ============================================================

-- Registra nuevo miembro del personal y su usuario del sistema.
CREATE OR REPLACE PROCEDURE sp_registrar_staff(
    p_nombre        VARCHAR,
    p_apellidos     VARCHAR,
    p_especialidad  VARCHAR,
    p_email         VARCHAR,
    p_id_rol        INT,
    p_username      VARCHAR,
    p_password_hash VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_staff INT;
BEGIN
    INSERT INTO staff (nombre, apellidos, especialidad, email, id_rol)
    VALUES (p_nombre, p_apellidos, p_especialidad, p_email, p_id_rol)
    RETURNING id_staff INTO v_id_staff;

    INSERT INTO usuario_sistema (username, password_hash, id_staff)
    VALUES (p_username, p_password_hash, v_id_staff);

    ok := 1; msg := 'Personal registrado con ID ' || v_id_staff;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualiza datos basicos de un miembro del personal.
CREATE OR REPLACE PROCEDURE sp_actualizar_staff(
    p_id_staff      INT,
    p_nombre        VARCHAR,
    p_apellidos     VARCHAR,
    p_especialidad  VARCHAR,
    p_email         VARCHAR,
    p_id_rol        INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE staff
    SET nombre       = p_nombre,
        apellidos    = p_apellidos,
        especialidad = p_especialidad,
        email        = p_email,
        id_rol       = p_id_rol
    WHERE id_staff = p_id_staff;

    IF NOT FOUND THEN
        ok := 0; msg := 'Personal no encontrado.';
    ELSE
        ok := 1; msg := 'Personal actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Activa o desactiva un miembro del personal.
CREATE OR REPLACE PROCEDURE sp_toggle_staff(
    p_id_staff  INT,
    OUT ok      INT,
    OUT msg     TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE staff SET activo = NOT activo WHERE id_staff = p_id_staff;
    IF NOT FOUND THEN
        ok := 0; msg := 'Personal no encontrado.';
    ELSE
        ok := 1; msg := 'Estado del personal actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- CUIDADO DIARIO
-- ============================================================

-- Registra check-in de estado de animo de un residente.
CREATE OR REPLACE PROCEDURE sp_checkin_estado_animo(
    p_id_residente  INT,
    p_id_cuidador   INT,
    p_puntaje       INT,
    p_notas         TEXT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO checkin_estado_animo (id_residente, id_cuidador, puntaje, notas)
    VALUES (p_id_residente, p_id_cuidador, p_puntaje, p_notas);
    ok := 1; msg := 'Check-in registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualiza tipo, descripcion y severidad de un incidente existente.
CREATE OR REPLACE PROCEDURE sp_actualizar_incidente(
    p_id_incidente  INT,
    p_tipo          VARCHAR,
    p_descripcion   TEXT,
    p_severidad     VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE reporte_incidente
    SET tipo        = p_tipo,
        descripcion = p_descripcion,
        severidad   = p_severidad
    WHERE id_incidente = p_id_incidente;

    IF NOT FOUND THEN
        ok := 0; msg := 'Incidente no encontrado.';
    ELSE
        ok := 1; msg := 'Incidente actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Registra un reporte de incidente.
CREATE OR REPLACE PROCEDURE sp_registrar_incidente(
    p_id_residente  INT,
    p_id_staff      INT,
    p_tipo          VARCHAR,
    p_descripcion   TEXT,
    p_severidad     VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO reporte_incidente (id_residente, id_staff, tipo, descripcion, severidad)
    VALUES (p_id_residente, p_id_staff, p_tipo, p_descripcion, p_severidad);
    ok := 1; msg := 'Incidente registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Elimina una sesion de terapia (solo el propio terapeuta puede borrarla).
CREATE OR REPLACE PROCEDURE sp_eliminar_sesion(
    p_id_sesion     INT,
    p_id_terapeuta  INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM sesion_terapia
    WHERE id_sesion = p_id_sesion AND id_terapeuta = p_id_terapeuta;
    IF NOT FOUND THEN
        ok := 0; msg := 'Sesion no encontrada o no pertenece a este terapeuta.';
    ELSE
        ok := 1; msg := 'Sesion eliminada.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- REPORTES CON GRAFICAS
-- ============================================================

-- Evolucion promedio de animo de todos los residentes por dia.
CREATE OR REPLACE PROCEDURE sp_evolucion_animo_global(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        DATE(fecha_registro)            AS fecha,
        ROUND(AVG(puntaje), 2)          AS puntaje_promedio,
        COUNT(*)                        AS num_registros
    FROM checkin_estado_animo
    WHERE fecha_registro >= NOW() - (p_dias || ' days')::INTERVAL
    GROUP BY DATE(fecha_registro)
    ORDER BY fecha;
END;
$$;


-- Incidentes agrupados por tipo y severidad (ultimos N dias).
CREATE OR REPLACE PROCEDURE sp_incidentes_por_severidad(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        tipo,
        severidad,
        COUNT(*) AS total
    FROM reporte_incidente
    WHERE fecha >= NOW() - (p_dias || ' days')::INTERVAL
    GROUP BY tipo, severidad
    ORDER BY tipo, severidad;
END;
$$;


-- Adherencia terapeutica: sesiones programadas vs realizadas por terapeuta.
CREATE OR REPLACE PROCEDURE sp_adherencia_terapeutica(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.nombre || ' ' || s.apellidos                                              AS terapeuta,
        COUNT(st.id_sesion)                                                         AS total_programadas,
        COUNT(st.id_sesion) FILTER (WHERE st.asistio = TRUE)                        AS realizadas,
        COUNT(st.id_sesion) FILTER (WHERE st.asistio = FALSE)                       AS no_realizadas
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol AND r.nivel_acceso = 2
    LEFT JOIN sesion_terapia st
           ON st.id_terapeuta = s.id_staff
          AND st.fecha_sesion >= NOW() - (p_dias || ' days')::INTERVAL
    WHERE s.activo = TRUE
    GROUP BY s.id_staff, s.nombre, s.apellidos
    ORDER BY total_programadas DESC;
END;
$$;


-- Resumen de eventos IoT por tipo (ultimos N dias).
CREATE OR REPLACE PROCEDURE sp_resumen_iot(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT tipo_evento, total FROM (
        SELECT 'GPS'    AS tipo_evento, COUNT(*) AS total
          FROM gps_ping WHERE registrado_en >= NOW() - (p_dias || ' days')::INTERVAL
        UNION ALL
        SELECT 'NFC',    COUNT(*) FROM nfc_evento
          WHERE escaneado_en >= NOW() - (p_dias || ' days')::INTERVAL
        UNION ALL
        SELECT 'RFID',   COUNT(*) FROM acceso_rfid
          WHERE accedido_en >= NOW() - (p_dias || ' days')::INTERVAL
        UNION ALL
        SELECT 'Beacon', COUNT(*) FROM deteccion_beacon
          WHERE detectado_en >= NOW() - (p_dias || ' days')::INTERVAL
    ) t
    ORDER BY tipo_evento;
END;
$$;


-- Carga operativa por profesional: sesiones, check-ins e incidentes en N dias.
CREATE OR REPLACE PROCEDURE sp_carga_operativa(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.nombre || ' ' || s.apellidos                                              AS profesional,
        r.nombre_rol                                                                 AS rol,
        COUNT(DISTINCT st.id_sesion)    FILTER (WHERE st.id_sesion    IS NOT NULL)  AS sesiones,
        COUNT(DISTINCT c.id_checkin)    FILTER (WHERE c.id_checkin    IS NOT NULL)  AS checkins,
        COUNT(DISTINCT ri.id_incidente) FILTER (WHERE ri.id_incidente IS NOT NULL)  AS incidentes
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    LEFT JOIN sesion_terapia st
           ON st.id_terapeuta = s.id_staff
          AND st.fecha_sesion  >= NOW() - (p_dias || ' days')::INTERVAL
    LEFT JOIN checkin_estado_animo c
           ON c.id_cuidador   = s.id_staff
          AND c.fecha_registro >= NOW() - (p_dias || ' days')::INTERVAL
    LEFT JOIN reporte_incidente ri
           ON ri.id_staff = s.id_staff
          AND ri.fecha    >= NOW() - (p_dias || ' days')::INTERVAL
    WHERE s.activo = TRUE
    GROUP BY s.id_staff, s.nombre, s.apellidos, r.nombre_rol
    ORDER BY (COUNT(DISTINCT st.id_sesion) + COUNT(DISTINCT c.id_checkin)) DESC;
END;
$$;


-- ============================================================
-- LISTAS DE CATALOGOS (usadas por los dropdowns del frontend)
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_lista_residentes_activos(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_residente,
           nombre || ' ' || apellidos AS nombre,
           habitacion
    FROM residente
    WHERE activo = TRUE
    ORDER BY apellidos;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_lista_roles(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_rol, nombre_rol, nivel_acceso
    FROM rol
    ORDER BY nivel_acceso;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_lista_cuidadores(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT s.id_staff,
           s.nombre || ' ' || s.apellidos AS nombre,
           s.especialidad
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    WHERE r.nombre_rol = 'Cuidador' AND s.activo = TRUE
    ORDER BY s.apellidos;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_lista_staff(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT s.id_staff,
           s.nombre,
           s.apellidos,
           s.especialidad,
           s.email,
           s.activo,
           s.fecha_alta,
           r.id_rol,
           r.nombre_rol,
           r.nivel_acceso,
           TO_CHAR(s.fecha_alta, 'DD Mon YYYY') AS fecha_alta_fmt
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    ORDER BY s.activo DESC, s.apellidos;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_lista_staff_activo(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT s.id_staff,
           s.nombre || ' ' || s.apellidos AS nombre,
           s.apellidos,
           s.especialidad,
           r.nombre_rol,
           r.nivel_acceso
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    WHERE s.activo = TRUE
    ORDER BY s.apellidos;
END;
$$;


-- Devuelve todos los lectores RFID instalados con su ala y tipo de zona.
DROP PROCEDURE IF EXISTS sp_lectores_rfid(refcursor);
CREATE OR REPLACE PROCEDURE sp_lectores_rfid(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        lr.id_lector,
        lr.ubicacion                    AS nombre_lector,
        NULL::TEXT                      AS sala,
        a.nombre                        AS ala,
        lr.es_restringido               AS zona_restringida
    FROM lector_rfid lr
    LEFT JOIN ala a ON a.id_ala = lr.id_ala
    ORDER BY lr.ubicacion;
END;
$$;


-- ============================================================
-- MEDICAMENTOS — horarios y catalogos
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_lista_medicamentos(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_medicamento, nombre, descripcion, unidad
    FROM medicamento
    ORDER BY nombre;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_lista_horarios_medicamento(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT hm.id_horario,
           hm.id_residente,
           r.nombre || ' ' || r.apellidos                      AS residente,
           hm.id_medicamento,
           m.nombre                                             AS medicamento,
           m.unidad,
           hm.hora_programada,
           hm.dosis,
           hm.frecuencia,
           hm.activo,
           TO_CHAR(hm.hora_programada, 'HH24:MI')              AS hora_fmt
    FROM horario_medicamento hm
    JOIN residente   r ON r.id_residente    = hm.id_residente
    JOIN medicamento m ON m.id_medicamento  = hm.id_medicamento
    ORDER BY r.apellidos, hm.hora_programada;
END;
$$;


DROP PROCEDURE IF EXISTS sp_registrar_horario_medicamento(integer,integer,time,varchar,varchar,integer,boolean,text);
DROP PROCEDURE IF EXISTS sp_registrar_horario_medicamento(integer,integer,time,varchar,varchar,boolean,text,integer);
CREATE OR REPLACE PROCEDURE sp_registrar_horario_medicamento(
    p_id_residente   INT,
    p_id_medicamento INT,
    p_hora           TIME,
    p_dosis          VARCHAR,
    p_frecuencia     VARCHAR,
    OUT p_ok         BOOLEAN,
    OUT p_msg        TEXT,
    OUT p_id_horario INT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO horario_medicamento
        (id_residente, id_medicamento, hora_programada, dosis, frecuencia, activo)
    VALUES
        (p_id_residente, p_id_medicamento, p_hora, p_dosis, p_frecuencia, TRUE)
    RETURNING id_horario INTO p_id_horario;

    p_ok  := TRUE;
    p_msg := 'Horario registrado correctamente.';
EXCEPTION WHEN OTHERS THEN
    p_ok  := FALSE;
    p_msg := SQLERRM;
    p_id_horario := NULL;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_toggle_horario_medicamento(
    p_id_horario INT,
    OUT p_ok     BOOLEAN,
    OUT p_msg    TEXT,
    OUT p_activo BOOLEAN
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE horario_medicamento
    SET activo = NOT activo
    WHERE id_horario = p_id_horario
    RETURNING activo INTO p_activo;

    IF NOT FOUND THEN
        p_ok  := FALSE;
        p_msg := 'Horario no encontrado.';
    ELSE
        p_ok  := TRUE;
        p_msg := CASE WHEN p_activo THEN 'Horario activado.' ELSE 'Horario desactivado.' END;
    END IF;
EXCEPTION WHEN OTHERS THEN
    p_ok  := FALSE;
    p_msg := SQLERRM;
END;
$$;


-- ============================================================
-- CATALOGO DE MEDICAMENTOS
-- ============================================================

DROP PROCEDURE IF EXISTS sp_registrar_medicamento(varchar,text,varchar,integer,boolean,text);
DROP PROCEDURE IF EXISTS sp_registrar_medicamento(varchar,text,varchar,boolean,text,integer);
CREATE OR REPLACE PROCEDURE sp_registrar_medicamento(
    p_nombre      VARCHAR,
    p_descripcion TEXT,
    p_unidad      VARCHAR,
    OUT p_ok  BOOLEAN,
    OUT p_msg TEXT,
    OUT p_id  INT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO medicamento (nombre, descripcion, unidad)
    VALUES (p_nombre, p_descripcion, p_unidad)
    RETURNING id_medicamento INTO p_id;
    p_ok  := TRUE;
    p_msg := 'Medicamento registrado.';
EXCEPTION
    WHEN unique_violation THEN
        p_ok := FALSE; p_id := NULL;
        p_msg := 'Ya existe un medicamento con ese nombre.';
    WHEN OTHERS THEN
        p_ok := FALSE; p_msg := SQLERRM; p_id := NULL;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_actualizar_medicamento(
    p_id          INT,
    p_nombre      VARCHAR,
    p_descripcion TEXT,
    p_unidad      VARCHAR,
    OUT p_ok  BOOLEAN,
    OUT p_msg TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE medicamento
    SET nombre = p_nombre, descripcion = p_descripcion, unidad = p_unidad
    WHERE id_medicamento = p_id;
    p_ok  := TRUE;
    p_msg := 'Medicamento actualizado.';
EXCEPTION
    WHEN unique_violation THEN
        p_ok := FALSE;
        p_msg := 'Ya existe un medicamento con ese nombre.';
    WHEN OTHERS THEN
        p_ok := FALSE; p_msg := SQLERRM;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_eliminar_medicamento(
    p_id  INT,
    OUT p_ok  BOOLEAN,
    OUT p_msg TEXT
)
LANGUAGE plpgsql AS $$
DECLARE v_uso INT;
BEGIN
    SELECT COUNT(*) INTO v_uso FROM horario_medicamento WHERE id_medicamento = p_id;
    IF v_uso > 0 THEN
        p_ok  := FALSE;
        p_msg := 'No se puede eliminar: tiene ' || v_uso || ' horario(s) asociado(s).';
        RETURN;
    END IF;
    DELETE FROM medicamento WHERE id_medicamento = p_id;
    p_ok  := TRUE;
    p_msg := 'Medicamento eliminado.';
EXCEPTION WHEN OTHERS THEN
    p_ok := FALSE; p_msg := SQLERRM;
END;
$$;


-- ============================================================
-- TURNOS DE PERSONAL
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_lista_alas(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_ala, nombre, piso FROM ala WHERE activa = TRUE ORDER BY piso, nombre;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_lista_turnos(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT t.id_turno,
           t.fecha,
           TO_CHAR(t.fecha, 'DD Mon YYYY')          AS fecha_fmt,
           t.hora_inicio,
           t.hora_fin,
           TO_CHAR(t.hora_inicio, 'HH24:MI')        AS inicio_fmt,
           TO_CHAR(t.hora_fin,    'HH24:MI')        AS fin_fmt,
           s.nombre || ' ' || s.apellidos           AS staff,
           s.especialidad,
           r.nombre_rol                              AS rol,
           a.nombre                                  AS ala
    FROM turno t
    JOIN staff s ON s.id_staff = t.id_staff
    JOIN rol   r ON r.id_rol   = s.id_rol
    JOIN ala   a ON a.id_ala   = t.id_ala
    WHERE t.fecha >= CURRENT_DATE - INTERVAL '7 days'
    ORDER BY t.fecha DESC, t.hora_inicio;
END;
$$;


DROP PROCEDURE IF EXISTS sp_registrar_turno(integer,integer,date,time,time,integer,boolean,text);
DROP PROCEDURE IF EXISTS sp_registrar_turno(integer,integer,date,time,time,boolean,text,integer);
CREATE OR REPLACE PROCEDURE sp_registrar_turno(
    p_id_staff    INT,
    p_id_ala      INT,
    p_fecha       DATE,
    p_hora_inicio TIME,
    p_hora_fin    TIME,
    OUT p_ok  BOOLEAN,
    OUT p_msg TEXT,
    OUT p_id  INT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO turno (id_staff, id_ala, fecha, hora_inicio, hora_fin)
    VALUES (p_id_staff, p_id_ala, p_fecha, p_hora_inicio, p_hora_fin)
    RETURNING id_turno INTO p_id;
    p_ok  := TRUE;
    p_msg := 'Turno agregado correctamente.';
EXCEPTION WHEN OTHERS THEN
    p_ok := FALSE; p_msg := SQLERRM; p_id := NULL;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_eliminar_turno(
    p_id  INT,
    OUT p_ok  BOOLEAN,
    OUT p_msg TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM turno WHERE id_turno = p_id;
    IF NOT FOUND THEN
        p_ok := FALSE; p_msg := 'Turno no encontrado.';
    ELSE
        p_ok := TRUE; p_msg := 'Turno eliminado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    p_ok := FALSE; p_msg := SQLERRM;
END;
$$;


-- ============================================================
-- DASHBOARDS — estadísticas resumen por rol
-- ============================================================

DROP PROCEDURE IF EXISTS sp_dashboard_admin(refcursor);
CREATE OR REPLACE PROCEDURE sp_dashboard_admin(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        (SELECT COUNT(*) FROM residente WHERE activo = TRUE)::INT              AS total_residentes,
        (SELECT COUNT(*) FROM staff    WHERE activo = TRUE)::INT              AS total_staff,
        (SELECT COUNT(*) FROM reporte_incidente
          WHERE severidad = 'Alta'
            AND fecha >= NOW() - INTERVAL '7 days')::INT                      AS incidentes_alta,
        (SELECT COUNT(*) FROM v_medicamentos_pendientes_hoy)::INT             AS meds_pendientes;
END;
$$;


DROP PROCEDURE IF EXISTS sp_dashboard_terapeuta(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_dashboard_terapeuta(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        (SELECT COUNT(DISTINCT a.id_residente)
           FROM asignacion a
          WHERE a.id_staff  = p_id_staff
            AND a.fecha_fin IS NULL)::INT                                      AS total_residentes,
        (SELECT COUNT(*) FROM reporte_incidente ri
           JOIN asignacion a ON a.id_residente = ri.id_residente
                             AND a.id_staff    = p_id_staff
                             AND a.fecha_fin  IS NULL
          WHERE ri.fecha >= NOW() - INTERVAL '7 days')::INT                   AS incidentes_activos,
        (SELECT ROUND(AVG(cea.puntaje)::NUMERIC, 1)
           FROM checkin_estado_animo cea
           JOIN asignacion a ON a.id_residente = cea.id_residente
                             AND a.id_staff    = p_id_staff
                             AND a.fecha_fin  IS NULL
          WHERE cea.fecha_registro >= NOW() - INTERVAL '7 days')             AS animo_promedio;
END;
$$;


DROP PROCEDURE IF EXISTS sp_dashboard_cuidador(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_dashboard_cuidador(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        (SELECT COUNT(*) FROM checkin_estado_animo cea
           JOIN asignacion a ON a.id_residente = cea.id_residente
                             AND a.id_staff    = p_id_staff
                             AND a.fecha_fin  IS NULL
          WHERE cea.fecha_registro::DATE = CURRENT_DATE)::INT                 AS checkins_hoy,
        (SELECT COUNT(*) FROM reporte_incidente ri
           JOIN asignacion a ON a.id_residente = ri.id_residente
                             AND a.id_staff    = p_id_staff
                             AND a.fecha_fin  IS NULL
          WHERE ri.fecha::DATE = CURRENT_DATE)::INT                          AS incidentes_hoy;
END;
$$;


-- ─── IDs de residentes asignados a un cuidador ───────────────────────────────
DROP PROCEDURE IF EXISTS sp_ids_residentes_cuidador(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_ids_residentes_cuidador(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT a.id_residente
    FROM asignacion a
    WHERE a.id_staff  = p_id_staff
      AND a.tipo_rol  = 'Cuidador'
      AND a.fecha_fin IS NULL;
END;
$$;


-- ─── Medicamentos pendientes hoy para los residentes de un cuidador ──────────
DROP PROCEDURE IF EXISTS sp_meds_pendientes_cuidador(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_meds_pendientes_cuidador(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        r.nombre || ' ' || r.apellidos          AS residente,
        r.habitacion,
        m.nombre                                 AS medicamento,
        hm.dosis,
        TO_CHAR(hm.hora_programada, 'HH12:MI AM') AS hora_programada,
        NULL::TEXT                               AS via_administracion
    FROM horario_medicamento hm
    JOIN residente   r  ON hm.id_residente   = r.id_residente
    JOIN medicamento m  ON hm.id_medicamento = m.id_medicamento
    JOIN asignacion  a  ON a.id_residente    = hm.id_residente
                       AND a.id_staff        = p_id_staff
                       AND a.tipo_rol        = 'Cuidador'
                       AND a.fecha_fin       IS NULL
    WHERE hm.activo = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM log_medicamento lm
          WHERE lm.id_horario = hm.id_horario
            AND lm.fecha_administracion::DATE = CURRENT_DATE
      )
    ORDER BY hm.hora_programada;
END;
$$;


-- ─── Medicamentos ya administrados hoy para los residentes de un cuidador ────
DROP PROCEDURE IF EXISTS sp_medicamentos_admin_hoy(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_medicamentos_admin_hoy(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        r.nombre || ' ' || r.apellidos                  AS residente,
        m.nombre                                         AS medicamento,
        hm.dosis,
        TO_CHAR(lm.fecha_administracion, 'HH12:MI AM')  AS hora_administrado,
        sf.nombre || ' ' || sf.apellidos                AS confirmado_por,
        NULL::TEXT                                       AS metodo
    FROM log_medicamento      lm
    JOIN horario_medicamento  hm ON lm.id_horario       = hm.id_horario
    JOIN medicamento          m  ON hm.id_medicamento   = m.id_medicamento
    JOIN residente            r  ON hm.id_residente     = r.id_residente
    JOIN staff                sf ON lm.id_cuidador      = sf.id_staff
    JOIN asignacion           a  ON a.id_residente      = hm.id_residente
                                AND a.id_staff          = p_id_staff
                                AND a.tipo_rol          = 'Cuidador'
                                AND a.fecha_fin         IS NULL
    WHERE lm.fecha_administracion::DATE = CURRENT_DATE
    ORDER BY lm.fecha_administracion DESC;
END;
$$;


-- ─── Checkins de ánimo recientes de los residentes de un cuidador ────────────
DROP PROCEDURE IF EXISTS sp_animo_bajo_cuidador(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_animo_bajo_cuidador(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT DISTINCT ON (cea.id_residente)
        r.nombre || ' ' || r.apellidos AS residente,
        cea.puntaje
    FROM checkin_estado_animo cea
    JOIN residente  r ON cea.id_residente = r.id_residente
    JOIN asignacion a ON a.id_residente   = cea.id_residente
                     AND a.id_staff       = p_id_staff
                     AND a.tipo_rol       = 'Cuidador'
                     AND a.fecha_fin      IS NULL
    WHERE cea.fecha_registro >= NOW() - INTERVAL '7 days'
    ORDER BY cea.id_residente, cea.fecha_registro DESC;
END;
$$;


-- ─── Asignaciones activas de un residente ────────────────────────────────────
DROP PROCEDURE IF EXISTS sp_asignaciones_residente(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_asignaciones_residente(
    p_id_residente INT,
    p_cursor       REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT a.id_asignacion,
           s.id_staff,
           s.nombre || ' ' || s.apellidos AS staff_nombre,
           a.tipo_rol,
           a.es_principal,
           a.fecha_inicio
    FROM asignacion a
    JOIN staff s ON a.id_staff = s.id_staff
    WHERE a.id_residente = p_id_residente
      AND a.fecha_fin IS NULL
    ORDER BY a.es_principal DESC, a.tipo_rol;
END;
$$;


-- ─── Cambiar cuidador principal de un residente ───────────────────────────────
DROP PROCEDURE IF EXISTS sp_cambiar_cuidador(integer,integer,integer,text);
CREATE OR REPLACE PROCEDURE sp_cambiar_cuidador(
    p_id_residente      INT,
    p_id_nuevo_cuidador INT,
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Cerrar asignaciones de Cuidador vigentes
    UPDATE asignacion
       SET fecha_fin = CURRENT_DATE
     WHERE id_residente = p_id_residente
       AND tipo_rol     = 'Cuidador'
       AND fecha_fin    IS NULL;

    -- Registrar nuevo cuidador principal
    INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal)
    VALUES (p_id_residente, p_id_nuevo_cuidador, 'Cuidador', TRUE);

    ok  := 1;
    msg := 'Cuidador actualizado correctamente.';
EXCEPTION WHEN OTHERS THEN
    ok  := 0;
    msg := 'Error: ' || SQLERRM;
END;
$$;


-- ─── Sesiones de hoy para un terapeuta ───────────────────────────────────────
DROP PROCEDURE IF EXISTS sp_sesiones_hoy_terapeuta(integer,refcursor);
CREATE OR REPLACE PROCEDURE sp_sesiones_hoy_terapeuta(
    p_id_staff  INT,
    p_cursor    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT
        TO_CHAR(st.fecha_sesion, 'HH12:MI AM') AS hora_inicio,
        st.duracion_min,
        r.nombre || ' ' || r.apellidos          AS residente,
        st.tipo_sesion,
        s.nombre                                 AS sala
    FROM sesion_terapia st
    JOIN residente r ON st.id_residente = r.id_residente
    JOIN sala      s ON st.id_sala      = s.id_sala
    WHERE st.id_terapeuta       = p_id_staff
      AND st.fecha_sesion::DATE = CURRENT_DATE
    ORDER BY st.fecha_sesion;
END;
$$;
