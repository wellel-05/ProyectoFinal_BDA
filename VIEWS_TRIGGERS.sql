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
CREATE OR REPLACE VIEW v_accesos_rfid_hoy AS
SELECT
    ar.id_acceso,
    s.nombre || ' ' || s.apellidos     AS staff,
    s.especialidad,
    lr.ubicacion,
    a.nombre                            AS ala,
    lr.es_restringido,
    ar.acceso_concedido,
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
        v_id_usuario := 0;
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

CREATE TRIGGER trg_before_delete_log_medicamento
BEFORE DELETE ON log_medicamento
FOR EACH ROW EXECUTE FUNCTION trg_proteger_log_medicamento();
