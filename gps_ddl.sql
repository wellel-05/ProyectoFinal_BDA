-- GPS tracking — ElderCare
-- Run: psql -U postgres -d eldercare -f gps_ddl.sql

CREATE TABLE IF NOT EXISTS dispositivo_gps (
    id_dispositivo SERIAL PRIMARY KEY,
    device_id      VARCHAR(100) UNIQUE NOT NULL,
    id_residente   INT REFERENCES residente(id_residente) ON DELETE SET NULL,
    nombre         VARCHAR(100),
    activo         BOOLEAN DEFAULT TRUE,
    fecha_alta     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS posicion_gps (
    id_posicion    BIGSERIAL PRIMARY KEY,
    device_id      VARCHAR(100) NOT NULL,
    latitud        DECIMAL(10,7) NOT NULL,
    longitud       DECIMAL(11,7) NOT NULL,
    altitud        DECIMAL(8,2),
    velocidad_kmh  DECIMAL(6,2),
    rumbo          DECIMAL(5,1),
    precision_m    DECIMAL(8,2),
    bateria        SMALLINT,
    ts_dispositivo TIMESTAMPTZ,
    ts_servidor    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_posicion_device_ts
    ON posicion_gps (device_id, ts_servidor DESC);

CREATE TABLE IF NOT EXISTS zona_gps (
    id_zona     SERIAL PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    descripcion TEXT,
    latitud     DECIMAL(10,7) NOT NULL,
    longitud    DECIMAL(11,7) NOT NULL,
    radio_m     INTEGER NOT NULL DEFAULT 50,
    tipo        VARCHAR(20) NOT NULL DEFAULT 'peligrosa'
                    CHECK (tipo IN ('peligrosa','segura')),
    color       VARCHAR(7)  DEFAULT '#EF4444',
    activo      BOOLEAN DEFAULT TRUE,
    creado_en   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alerta_gps (
    id_alerta  BIGSERIAL PRIMARY KEY,
    device_id  VARCHAR(100) NOT NULL,
    id_zona    INT REFERENCES zona_gps(id_zona) ON DELETE SET NULL,
    tipo       VARCHAR(50) NOT NULL,
    latitud    DECIMAL(10,7),
    longitud   DECIMAL(11,7),
    mensaje    TEXT,
    atendida   BOOLEAN DEFAULT FALSE,
    ts_alerta  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_alerta_pendiente
    ON alerta_gps (atendida, ts_alerta DESC);
