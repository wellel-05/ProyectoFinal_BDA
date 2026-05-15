-- NFC: actividades y registro de asistencias
-- Ejecutar como equipo5proyfin en asilo_db

CREATE TABLE IF NOT EXISTS actividad (
    id_actividad    SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    tipo            VARCHAR(20)  NOT NULL DEFAULT 'grupal'
                    CHECK (tipo IN ('grupal','individual','terapia','recreativa')),
    descripcion     TEXT,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMP    NOT NULL DEFAULT NOW(),
    id_staff_crea   INT REFERENCES staff(id_staff) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS asistencia_nfc (
    id_asistencia   BIGSERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL REFERENCES residente(id_residente) ON DELETE CASCADE,
    id_actividad    INT          NOT NULL REFERENCES actividad(id_actividad) ON DELETE RESTRICT,
    id_staff        INT          REFERENCES staff(id_staff) ON DELETE SET NULL,
    ts_registro     TIMESTAMP    NOT NULL DEFAULT NOW(),
    notas           TEXT,
    metodo          VARCHAR(10)  NOT NULL DEFAULT 'nfc'
                    CHECK (metodo IN ('nfc','manual'))
);

CREATE INDEX IF NOT EXISTS ix_asistencia_residente ON asistencia_nfc(id_residente, ts_registro DESC);
CREATE INDEX IF NOT EXISTS ix_asistencia_actividad ON asistencia_nfc(id_actividad, ts_registro DESC);

-- Actividades de ejemplo
INSERT INTO actividad (nombre, tipo, descripcion) VALUES
  ('Terapia física grupal',  'grupal',      'Ejercicios de movilidad en salón principal'),
  ('Sesión de musicoterapia','terapia',     'Sesión grupal de estimulación auditiva'),
  ('Terapia ocupacional',    'individual',  'Actividades manuales individualizadas'),
  ('Recreación y juegos',    'recreativa',  'Juegos de mesa y actividades lúdicas')
ON CONFLICT DO NOTHING;
