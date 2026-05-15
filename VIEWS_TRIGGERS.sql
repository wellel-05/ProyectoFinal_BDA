-- ============================================================
--  VIEWS & TRIGGERS — ASILO SALUD MENTAL
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  Ejecutar despues de DDL.sql y PROCEDURES.sql
-- ============================================================


-- ============================================================
-- VIEWS
-- ============================================================

-- Vista principal de residentes activos con su cuidador principal,
-- ultimo puntaje de animo y ala/habitacion.
CREATE OR REPLACE VIEW v_residentes_resumen AS
SELECT
    r.id_residente,
    r.nombre || ' ' || r.apellidos                          AS residente,
    r.habitacion,
    r.diagnostico_principal,
    r.nivel_movilidad,
    EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT          AS edad,
    s.nombre || ' ' || s.apellidos                          AS cuidador_principal,
    c.puntaje                                               AS ultimo_puntaje_animo,
    TO_CHAR(c.fecha_registro, 'DD Mon HH12:MI AM')          AS fecha_ultimo_checkin,
    r.fecha_ingreso
FROM residente r
LEFT JOIN asignacion a
       ON a.id_residente = r.id_residente
      AND a.tipo_rol     = 'Cuidador'
      AND a.es_principal = TRUE
      AND a.fecha_fin   IS NULL
LEFT JOIN staff s ON s.id_staff = a.id_staff
LEFT JOIN LATERAL (
    SELECT puntaje, fecha_registro
    FROM checkin_estado_animo
    WHERE id_residente = r.id_residente
    ORDER BY fecha_registro DESC
    LIMIT 1
) c ON TRUE
WHERE r.activo = TRUE
ORDER BY r.apellidos;


-- Medicamentos programados para hoy que aun no tienen log de administracion.
CREATE OR REPLACE VIEW v_medicamentos_pendientes_hoy AS
SELECT
    hm.id_horario,
    r.id_residente,
    r.nombre || ' ' || r.apellidos     AS residente,
    r.habitacion,
    m.nombre                           AS medicamento,
    hm.dosis,
    hm.hora_programada,
    s.nombre || ' ' || s.apellidos     AS cuidador_asignado
FROM horario_medicamento hm
JOIN residente   r  ON hm.id_residente   = r.id_residente
JOIN medicamento m  ON hm.id_medicamento = m.id_medicamento
LEFT JOIN asignacion a
       ON a.id_residente = r.id_residente
      AND a.tipo_rol     = 'Cuidador'
      AND a.es_principal = TRUE
      AND a.fecha_fin   IS NULL
LEFT JOIN staff  s  ON s.id_staff = a.id_staff
WHERE hm.activo = TRUE
  AND r.activo  = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM log_medicamento lm
      WHERE lm.id_horario = hm.id_horario
        AND lm.fecha_administracion::DATE = CURRENT_DATE
  )
ORDER BY hm.hora_programada;


-- Sesiones de terapia del dia con terapeuta, residente y sala.
CREATE OR REPLACE VIEW v_sesiones_hoy AS
SELECT
    st.id_sesion,
    r.nombre  || ' ' || r.apellidos    AS residente,
    r.habitacion,
    s.nombre  || ' ' || s.apellidos    AS terapeuta,
    sa.nombre                           AS sala,
    st.tipo_sesion,
    st.duracion_min,
    TO_CHAR(st.fecha_sesion, 'HH12:MI AM') AS hora,
    st.asistio
FROM sesion_terapia st
JOIN residente r  ON st.id_residente = r.id_residente
JOIN staff     s  ON st.id_terapeuta = s.id_staff
JOIN sala      sa ON st.id_sala      = sa.id_sala
WHERE st.fecha_sesion::DATE = CURRENT_DATE
ORDER BY st.fecha_sesion;


-- Staff en turno hoy con su ala asignada.
CREATE OR REPLACE VIEW v_staff_en_turno_hoy AS
SELECT
    s.id_staff,
    s.nombre || ' ' || s.apellidos     AS staff,
    s.especialidad,
    r.nombre_rol                        AS rol,
    a.nombre                            AS ala,
    t.hora_inicio,
    t.hora_fin
FROM turno t
JOIN staff s ON t.id_staff = s.id_staff
JOIN ala   a ON t.id_ala   = a.id_ala
JOIN rol   r ON s.id_rol   = r.id_rol
WHERE t.fecha = CURRENT_DATE
  AND s.activo = TRUE
ORDER BY a.nombre, t.hora_inicio;


-- Accesos RFID del dia con nombre del staff y ubicacion del lector.
DROP VIEW IF EXISTS v_accesos_rfid_hoy;
CREATE OR REPLACE VIEW v_accesos_rfid_hoy AS
SELECT
    ar.id_acceso,
    s.nombre || ' ' || s.apellidos     AS staff,
    s.especialidad,
    lr.ubicacion,
    lr.ubicacion                        AS lector,
    a.nombre                            AS ala,
    lr.es_restringido,
    ar.acceso_concedido,
    ar.acceso_concedido                 AS autorizado,
    TO_CHAR(ar.accedido_en, 'HH12:MI AM') AS hora
FROM acceso_rfid ar
JOIN staff       s   ON ar.id_staff  = s.id_staff
JOIN lector_rfid lr  ON ar.id_lector = lr.id_lector
LEFT JOIN ala    a   ON lr.id_ala    = a.id_ala
WHERE ar.accedido_en::DATE = CURRENT_DATE
ORDER BY ar.accedido_en DESC;


-- Incidentes recientes (ultimos 7 dias) con severidad y residente.
CREATE OR REPLACE VIEW v_incidentes_recientes AS
SELECT
    ri.id_incidente,
    r.nombre  || ' ' || r.apellidos    AS residente,
    r.habitacion,
    s.nombre  || ' ' || s.apellidos    AS reportado_por,
    ri.tipo,
    ri.severidad,
    ri.descripcion,
    TO_CHAR(ri.fecha, 'DD Mon HH12:MI AM') AS fecha
FROM reporte_incidente ri
JOIN residente r ON ri.id_residente = r.id_residente
JOIN staff     s ON ri.id_staff     = s.id_staff
WHERE ri.fecha >= NOW() - INTERVAL '7 days'
ORDER BY
    CASE ri.severidad WHEN 'Alta' THEN 1 WHEN 'Media' THEN 2 ELSE 3 END,
    ri.fecha DESC;


-- Ultima ubicacion detectada por beacon de cada staff en turno hoy.
CREATE OR REPLACE VIEW v_ubicacion_actual_staff AS
SELECT
    s.id_staff,
    s.nombre || ' ' || s.apellidos     AS staff,
    s.especialidad,
    r.nombre_rol                        AS rol,
    a.nombre                            AS ala_detectada,
    TO_CHAR(db.detectado_en, 'HH12:MI AM') AS ultima_deteccion,
    EXTRACT(EPOCH FROM (NOW() - db.detectado_en)) / 60 AS minutos_desde_deteccion
FROM staff s
JOIN rol   r ON s.id_rol = r.id_rol
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
ORDER BY a.nombre NULLS LAST, s.apellidos;


-- Estado GPS de residentes al aire libre (ultimo ping con validacion de limite).
CREATE OR REPLACE VIEW v_estado_gps_residentes AS
SELECT
    r.id_residente,
    r.nombre || ' ' || r.apellidos     AS residente,
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


-- ============================================================
-- STORED PROCEDURES DE SOPORTE A TRIGGERS
-- (logica de negocio invocada desde triggers)
-- ============================================================

-- Inserta incidente automatico. Llamado por triggers.
CREATE OR REPLACE PROCEDURE sp_crear_incidente_automatico(
    p_id_residente  INT,
    p_id_staff      INT,
    p_tipo          VARCHAR,
    p_descripcion   TEXT,
    p_severidad     VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO reporte_incidente (id_residente, id_staff, tipo, descripcion, severidad)
    VALUES (p_id_residente, p_id_staff, p_tipo, p_descripcion, p_severidad);
END;
$$;


-- ============================================================
-- TRIGGERS
-- ============================================================

-- ── Trigger 1: Auditoria en tabla staff ──────────────────────
CREATE OR REPLACE FUNCTION trg_auditoria_staff()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_id_usuario INT;
BEGIN
    BEGIN
        v_id_usuario := current_setting('app.id_usuario')::INT;
    EXCEPTION WHEN OTHERS THEN
        v_id_usuario := NULL;
    END;

    IF TG_OP = 'DELETE' THEN
        INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
        VALUES (v_id_usuario, 'staff', 'DELETE', OLD.id_staff);
    ELSE
        INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
        VALUES (v_id_usuario, 'staff', 'UPDATE', NEW.id_staff);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_staff ON staff;
CREATE TRIGGER trg_after_staff
AFTER UPDATE OR DELETE ON staff
FOR EACH ROW EXECUTE FUNCTION trg_auditoria_staff();


-- ── Trigger 2: Alerta automatica por animo bajo ──────────────
-- Cuando se registra un check-in con puntaje ≤ 2,
-- se genera un reporte de incidente automatico tipo 'Agitacion'.
CREATE OR REPLACE FUNCTION trg_alerta_animo_bajo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.puntaje <= 2 THEN
        CALL sp_crear_incidente_automatico(
            NEW.id_residente,
            NEW.id_cuidador,
            'Agitacion',
            'Alerta automatica: puntaje de animo bajo (' || NEW.puntaje || '/5) registrado por cuidador.',
            CASE WHEN NEW.puntaje = 1 THEN 'Alta' ELSE 'Media' END
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_checkin_animo ON checkin_estado_animo;
CREATE TRIGGER trg_after_checkin_animo
AFTER INSERT ON checkin_estado_animo
FOR EACH ROW EXECUTE FUNCTION trg_alerta_animo_bajo();


-- ── Trigger 3: Alerta automatica por GPS fuera de limite ─────
-- Cuando se inserta un ping GPS fuera del perimetro del jardin,
-- se genera un incidente automatico de tipo 'Deambulacion'.
CREATE OR REPLACE FUNCTION trg_alerta_gps_fuera_limite()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_dentro    BOOLEAN;
    v_id_staff  INT;
BEGIN
    SELECT (NEW.latitud  BETWEEN lat_min AND lat_max
        AND NEW.longitud BETWEEN lon_min AND lon_max)
    INTO v_dentro
    FROM limite_jardin
    LIMIT 1;

    IF NOT v_dentro THEN
        -- Buscar el cuidador principal asignado al residente
        SELECT a.id_staff INTO v_id_staff
        FROM asignacion a
        WHERE a.id_residente = NEW.id_residente
          AND a.tipo_rol     = 'Cuidador'
          AND a.es_principal = TRUE
          AND a.fecha_fin   IS NULL
        LIMIT 1;

        -- Fallback: usar staff ID 1 si no hay cuidador asignado
        v_id_staff := COALESCE(v_id_staff, 1);

        CALL sp_crear_incidente_automatico(
            NEW.id_residente,
            v_id_staff,
            'Deambulacion',
            'Alerta GPS: residente detectado fuera del perimetro del jardin. '
            || 'Coords: (' || NEW.latitud || ', ' || NEW.longitud || ').',
            'Alta'
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_gps_ping ON gps_ping;
CREATE TRIGGER trg_after_gps_ping
AFTER INSERT ON gps_ping
FOR EACH ROW EXECUTE FUNCTION trg_alerta_gps_fuera_limite();


-- ── Trigger 4: Auditoria en acceso_rfid ──────────────────────
-- Registra en log_auditoria cada acceso a zona restringida.
CREATE OR REPLACE FUNCTION trg_auditoria_acceso_rfid()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_id_usuario    INT;
    v_es_restringido BOOLEAN;
BEGIN
    SELECT es_restringido INTO v_es_restringido
    FROM lector_rfid WHERE id_lector = NEW.id_lector;

    IF v_es_restringido THEN
        -- Buscar el usuario_sistema correspondiente al staff
        SELECT id_usuario INTO v_id_usuario
        FROM usuario_sistema
        WHERE id_staff = NEW.id_staff AND activo = TRUE
        LIMIT 1;

        IF v_id_usuario IS NOT NULL THEN
            INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
            VALUES (v_id_usuario, 'acceso_rfid', 'INSERT', NEW.id_acceso);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_acceso_rfid ON acceso_rfid;
CREATE TRIGGER trg_after_acceso_rfid
AFTER INSERT ON acceso_rfid
FOR EACH ROW EXECUTE FUNCTION trg_auditoria_acceso_rfid();


-- ── Trigger 5: Prevenir eliminacion de log_medicamento ───────
-- El historial de administracion de medicamentos es inmutable.
CREATE OR REPLACE FUNCTION trg_proteger_log_medicamento()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'El log de medicamentos es inmutable. No se permite DELETE.';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_before_delete_log_medicamento ON log_medicamento;
CREATE TRIGGER trg_before_delete_log_medicamento
BEFORE DELETE ON log_medicamento
FOR EACH ROW EXECUTE FUNCTION trg_proteger_log_medicamento();


-- ── Trigger 6: Auditoria en tabla residente ───────────────────
-- Registra en log_auditoria cada INSERT, UPDATE y DELETE
-- sobre la tabla residente para cumplimiento y trazabilidad.
CREATE OR REPLACE FUNCTION trg_auditoria_residente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_id_usuario INT;
    v_operacion  VARCHAR(10);
    v_id_reg     INT;
BEGIN
    BEGIN
        v_id_usuario := current_setting('app.id_usuario')::INT;
    EXCEPTION WHEN OTHERS THEN
        v_id_usuario := NULL;
    END;

    IF TG_OP = 'DELETE' THEN
        v_operacion := 'DELETE';
        v_id_reg    := OLD.id_residente;
    ELSIF TG_OP = 'INSERT' THEN
        v_operacion := 'INSERT';
        v_id_reg    := NEW.id_residente;
    ELSE
        v_operacion := 'UPDATE';
        v_id_reg    := NEW.id_residente;
    END IF;

    INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
    VALUES (v_id_usuario, 'residente', v_operacion, v_id_reg);

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_after_residente ON residente;
CREATE TRIGGER trg_after_residente
AFTER INSERT OR UPDATE OR DELETE ON residente
FOR EACH ROW EXECUTE FUNCTION trg_auditoria_residente();


-- ── Trigger 7: Validar solapamiento de sesiones de terapia ────
-- Impide que un terapeuta quede asignado a dos sesiones al mismo
-- tiempo o que una sala sea reservada por dos sesiones simultaneas.
CREATE OR REPLACE FUNCTION trg_validar_sesion_terapia()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_fin_nueva      TIMESTAMP;
    v_conflicto_id   INT;
BEGIN
    v_fin_nueva := NEW.fecha_sesion + (NEW.duracion_min || ' minutes')::INTERVAL;

    -- Verificar conflicto de terapeuta
    SELECT id_sesion INTO v_conflicto_id
    FROM sesion_terapia
    WHERE id_terapeuta = NEW.id_terapeuta
      AND id_sesion   <> COALESCE(NEW.id_sesion, 0)
      AND fecha_sesion < v_fin_nueva
      AND (fecha_sesion + (duracion_min || ' minutes')::INTERVAL) > NEW.fecha_sesion
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Conflicto de agenda: el terapeuta ya tiene una sesion programada que se solapa (id_sesion=%).',
            v_conflicto_id;
    END IF;

    -- Verificar conflicto de sala
    SELECT id_sesion INTO v_conflicto_id
    FROM sesion_terapia
    WHERE id_sala   = NEW.id_sala
      AND id_sesion <> COALESCE(NEW.id_sesion, 0)
      AND fecha_sesion < v_fin_nueva
      AND (fecha_sesion + (duracion_min || ' minutes')::INTERVAL) > NEW.fecha_sesion
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Conflicto de sala: la sala ya esta reservada en ese horario (id_sesion=%).',
            v_conflicto_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_before_sesion_terapia ON sesion_terapia;
CREATE TRIGGER trg_before_sesion_terapia
BEFORE INSERT OR UPDATE ON sesion_terapia
FOR EACH ROW EXECUTE FUNCTION trg_validar_sesion_terapia();


-- ── Trigger 8: Auditoria en usuario_sistema ───────────────────
-- Registra creacion y modificacion de cuentas de usuario,
-- incluyendo cambios de password (sin guardar el hash).
CREATE OR REPLACE FUNCTION trg_auditoria_usuario_sistema()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_id_usuario INT;
BEGIN
    BEGIN
        v_id_usuario := current_setting('app.id_usuario')::INT;
    EXCEPTION WHEN OTHERS THEN
        v_id_usuario := NULL;
    END;

    INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
    VALUES (
        v_id_usuario,
        'usuario_sistema',
        TG_OP,
        NEW.id_usuario
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_usuario_sistema ON usuario_sistema;
CREATE TRIGGER trg_after_usuario_sistema
AFTER INSERT OR UPDATE ON usuario_sistema
FOR EACH ROW EXECUTE FUNCTION trg_auditoria_usuario_sistema();


-- ── Trigger 9: Validar integridad de reporte_incidente ────────
-- Antes de insertar o actualizar un incidente verifica que:
--   a) la severidad sea un valor valido del dominio,
--   b) la descripcion no este vacia si la severidad es Alta.
CREATE OR REPLACE FUNCTION trg_validar_incidente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    -- a) Severidad dentro del dominio permitido
    IF NEW.severidad NOT IN ('Alta', 'Media', 'Baja') THEN
        RAISE EXCEPTION
            'Severidad invalida: %. Valores permitidos: Alta, Media, Baja.',
            NEW.severidad;
    END IF;

    -- b) Incidentes de alta severidad deben tener descripcion
    IF NEW.severidad = 'Alta' AND (NEW.descripcion IS NULL OR TRIM(NEW.descripcion) = '') THEN
        RAISE EXCEPTION
            'Los incidentes de severidad Alta requieren una descripcion detallada.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_before_incidente ON reporte_incidente;
CREATE TRIGGER trg_before_incidente
BEFORE INSERT OR UPDATE ON reporte_incidente
FOR EACH ROW EXECUTE FUNCTION trg_validar_incidente();


-- ── Trigger 10: Bloquear eliminacion fisica de residentes ─────
-- Los residentes deben darse de baja logicamente (activo = FALSE).
-- Un DELETE fisico destruiria el historial clinico completo.
CREATE OR REPLACE FUNCTION trg_proteger_delete_residente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'No se permite eliminar fisicamente un residente (id=%). '
        'Use la baja logica: UPDATE residente SET activo = FALSE.',
        OLD.id_residente;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_before_delete_residente ON residente;
CREATE TRIGGER trg_before_delete_residente
BEFORE DELETE ON residente
FOR EACH ROW EXECUTE FUNCTION trg_proteger_delete_residente();


-- ============================================================
-- VIEWS ADICIONALES (para KPI y reportes)
-- ============================================================

-- Adherencia de medicamentos por residente:
-- porcentaje de dosis administradas vs programadas hoy.
CREATE OR REPLACE VIEW v_adherencia_medicamentos AS
SELECT
    r.id_residente,
    r.nombre || ' ' || r.apellidos                          AS residente,
    r.habitacion,
    COUNT(hm.id_horario)                                    AS dosis_programadas,
    COUNT(lm.id_log)                                        AS dosis_administradas,
    COUNT(hm.id_horario) - COUNT(lm.id_log)                AS dosis_pendientes,
    ROUND(
        COUNT(lm.id_log)::NUMERIC
        / NULLIF(COUNT(hm.id_horario), 0) * 100, 1
    )                                                       AS pct_adherencia
FROM residente r
JOIN horario_medicamento hm
     ON hm.id_residente = r.id_residente AND hm.activo = TRUE
LEFT JOIN log_medicamento lm
     ON lm.id_horario          = hm.id_horario
    AND lm.fecha_administracion::DATE = CURRENT_DATE
WHERE r.activo = TRUE
GROUP BY r.id_residente, r.nombre, r.apellidos, r.habitacion
ORDER BY pct_adherencia ASC NULLS LAST;


-- ============================================================
-- VIEWS PORTAL FAMILIAR
-- Exponen solo la información no sensible visible para familiares.
-- ============================================================

-- Info básica de residente visible para su familiar vinculado.
CREATE OR REPLACE VIEW v_familiar_residente_info AS
SELECT
    r.id_residente,
    r.nombre || ' ' || r.apellidos                              AS residente,
    r.habitacion,
    r.diagnostico_principal,
    r.nivel_movilidad,
    EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT              AS edad,
    r.fecha_ingreso,
    s.nombre || ' ' || s.apellidos                              AS cuidador_principal,
    c.puntaje                                                   AS ultimo_puntaje_animo,
    TO_CHAR(c.fecha_registro, 'DD Mon YYYY HH12:MI AM')         AS fecha_ultimo_checkin,
    fr.id_familiar,
    fr.parentesco,
    fr.es_contacto_principal
FROM residente r
JOIN familiar_residente fr ON fr.id_residente = r.id_residente AND fr.fecha_fin IS NULL
JOIN familiar f            ON f.id_familiar   = fr.id_familiar  AND f.activo = TRUE
LEFT JOIN asignacion a
       ON a.id_residente = r.id_residente
      AND a.tipo_rol     = 'Cuidador'
      AND a.es_principal = TRUE
      AND a.fecha_fin   IS NULL
LEFT JOIN staff s ON s.id_staff = a.id_staff
LEFT JOIN LATERAL (
    SELECT puntaje, fecha_registro
    FROM checkin_estado_animo
    WHERE id_residente = r.id_residente
    ORDER BY fecha_registro DESC
    LIMIT 1
) c ON TRUE
WHERE r.activo = TRUE;


-- Sesiones de terapia visibles para familiar (sin notas clínicas).
CREATE OR REPLACE VIEW v_familiar_sesiones AS
SELECT
    st.id_sesion,
    st.id_residente,
    s.nombre || ' ' || s.apellidos     AS terapeuta,
    sa.nombre                           AS sala,
    st.tipo_sesion,
    st.duracion_min,
    TO_CHAR(st.fecha_sesion, 'DD Mon YYYY HH12:MI AM') AS fecha_hora,
    st.asistio
FROM sesion_terapia st
JOIN staff s  ON st.id_terapeuta = s.id_staff
JOIN sala  sa ON st.id_sala      = sa.id_sala
ORDER BY st.fecha_sesion DESC;


-- Medicamentos programados y si fueron administrados hoy.
CREATE OR REPLACE VIEW v_familiar_medicamentos AS
SELECT
    hm.id_horario,
    hm.id_residente,
    m.nombre           AS medicamento,
    hm.dosis,
    hm.hora_programada,
    hm.frecuencia,
    EXISTS (
        SELECT 1 FROM log_medicamento lm
        WHERE lm.id_horario = hm.id_horario
          AND lm.fecha_administracion::DATE = CURRENT_DATE
    )                  AS administrado_hoy
FROM horario_medicamento hm
JOIN medicamento m ON hm.id_medicamento = m.id_medicamento
WHERE hm.activo = TRUE
ORDER BY hm.hora_programada;


-- Incidentes recientes (30 días) visibles para familiar.
-- La descripción clínica se oculta para tipos sensibles.
CREATE OR REPLACE VIEW v_familiar_incidentes AS
SELECT
    ri.id_incidente,
    ri.id_residente,
    ri.tipo,
    ri.severidad,
    TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha,
    CASE
        WHEN ri.tipo IN ('Caida', 'Deambulacion')
        THEN ri.descripcion
        ELSE 'Informacion clinica reservada.'
    END AS descripcion_visible
FROM reporte_incidente ri
WHERE ri.fecha >= NOW() - INTERVAL '30 days'
ORDER BY ri.fecha DESC;


-- Historial de estado de ánimo (30 días) para gráfica familiar.
-- Solo puntaje; sin notas del cuidador.
CREATE OR REPLACE VIEW v_familiar_animo AS
SELECT
    cea.id_residente,
    cea.fecha_registro,
    cea.puntaje,
    TO_CHAR(cea.fecha_registro, 'DD Mon') AS etiqueta
FROM checkin_estado_animo cea
WHERE cea.fecha_registro >= NOW() - INTERVAL '30 days'
ORDER BY cea.fecha_registro ASC;


-- Resumen mensual de incidentes agrupado por tipo y severidad.
-- Fuente de datos para KPI de tasa de eventos criticos.
CREATE OR REPLACE VIEW v_resumen_incidentes_mes AS
SELECT
    TO_CHAR(ri.fecha, 'YYYY-MM')       AS mes,
    ri.tipo,
    ri.severidad,
    COUNT(*)                           AS total,
    COUNT(DISTINCT ri.id_residente)    AS residentes_afectados,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (PARTITION BY TO_CHAR(ri.fecha, 'YYYY-MM')),
    1)                                 AS pct_del_mes
FROM reporte_incidente ri
WHERE ri.fecha >= NOW() - INTERVAL '6 months'
GROUP BY TO_CHAR(ri.fecha, 'YYYY-MM'), ri.tipo, ri.severidad
ORDER BY mes DESC, total DESC;


-- ============================================================
-- PERMISOS — restaurar GRANT tras DROP/CREATE de vistas
-- ============================================================
GRANT SELECT ON v_residentes_resumen           TO equipo5proyfin;
GRANT SELECT ON v_medicamentos_pendientes_hoy  TO equipo5proyfin;
GRANT SELECT ON v_sesiones_hoy                 TO equipo5proyfin;
GRANT SELECT ON v_staff_en_turno_hoy           TO equipo5proyfin;
GRANT SELECT ON v_accesos_rfid_hoy             TO equipo5proyfin;
GRANT SELECT ON v_incidentes_recientes         TO equipo5proyfin;
GRANT SELECT ON v_ubicacion_actual_staff       TO equipo5proyfin;
GRANT SELECT ON v_estado_gps_residentes        TO equipo5proyfin;
GRANT SELECT ON v_adherencia_medicamentos      TO equipo5proyfin;
GRANT SELECT ON v_familiar_residente_info      TO equipo5proyfin;
GRANT SELECT ON v_familiar_sesiones            TO equipo5proyfin;
GRANT SELECT ON v_familiar_medicamentos        TO equipo5proyfin;
GRANT SELECT ON v_familiar_incidentes          TO equipo5proyfin;
GRANT SELECT ON v_familiar_animo               TO equipo5proyfin;
GRANT SELECT ON v_resumen_incidentes_mes       TO equipo5proyfin;
