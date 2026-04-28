-- ============================================================
--  SISTEMA DE GESTION DE ASILO — SALUD MENTAL ADULTOS MAYORES
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  DDL PostgreSQL (Scope Final: Asilo)
-- ============================================================
-- PASO 1: Crear la base de datos (ejecutar como superusuario)
--   CREATE DATABASE asilo_db;
--   CREATE USER equipo5proyfin WITH PASSWORD '123';
--   GRANT ALL PRIVILEGES ON DATABASE asilo_db TO equipo5proyfin;
-- PASO 2: Conectarse a asilo_db y ejecutar este script.
-- ============================================================


-- ============================================================
-- TABLAS MAESTRAS / CATALOGOS
-- ============================================================

CREATE TABLE rol (
    id_rol          SERIAL PRIMARY KEY,
    nombre_rol      VARCHAR(50)  NOT NULL,
    nivel_acceso    INT          NOT NULL CHECK (nivel_acceso BETWEEN 1 AND 3),
    -- 1 = Administrador, 2 = Terapeuta/Medico, 3 = Cuidador
    CONSTRAINT uq_rol_nombre UNIQUE (nombre_rol)
);

CREATE TABLE ala (
    id_ala          SERIAL PRIMARY KEY,
    nombre          VARCHAR(80)  NOT NULL,
    piso            INT          NOT NULL DEFAULT 1 CHECK (piso >= 0),
    descripcion     TEXT,
    activa          BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_ala_nombre UNIQUE (nombre)
);

CREATE TABLE sala (
    id_sala         SERIAL PRIMARY KEY,
    nombre          VARCHAR(80)  NOT NULL,
    id_ala          INT          NOT NULL,
    capacidad       INT          NOT NULL DEFAULT 1 CHECK (capacidad > 0),
    CONSTRAINT uq_sala_nombre UNIQUE (nombre),
    CONSTRAINT fk_sala_ala FOREIGN KEY (id_ala)
        REFERENCES ala(id_ala) ON UPDATE CASCADE
);

-- Tabla de configuracion del jardin (una sola fila)
CREATE TABLE limite_jardin (
    id_limite       SERIAL PRIMARY KEY,
    descripcion     VARCHAR(100),
    lat_min         DECIMAL(10,7) NOT NULL,
    lat_max         DECIMAL(10,7) NOT NULL,
    lon_min         DECIMAL(10,7) NOT NULL,
    lon_max         DECIMAL(10,7) NOT NULL,
    CONSTRAINT ck_lat CHECK (lat_min < lat_max),
    CONSTRAINT ck_lon CHECK (lon_min < lon_max)
);

CREATE TABLE medicamento (
    id_medicamento  SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    descripcion     TEXT,
    unidad          VARCHAR(20)  NOT NULL DEFAULT 'mg',
    CONSTRAINT uq_medicamento_nombre UNIQUE (nombre)
);


-- ============================================================
-- PERSONAS
-- ============================================================

CREATE TABLE staff (
    id_staff        SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    apellidos       VARCHAR(100) NOT NULL,
    especialidad    VARCHAR(80)  NOT NULL,
    email           VARCHAR(100) NOT NULL,
    id_rol          INT          NOT NULL,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_alta      DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_staff_email UNIQUE (email),
    CONSTRAINT fk_staff_rol FOREIGN KEY (id_rol)
        REFERENCES rol(id_rol) ON UPDATE CASCADE
);

-- Auth desacoplada de la identidad clinica
CREATE TABLE usuario_sistema (
    id_usuario      SERIAL PRIMARY KEY,
    username        VARCHAR(50)  NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    id_staff        INT          NOT NULL,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_login    TIMESTAMP,
    CONSTRAINT uq_usuario_username UNIQUE (username),
    CONSTRAINT fk_usuario_staff FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE residente (
    id_residente        SERIAL PRIMARY KEY,
    nombre              VARCHAR(100) NOT NULL,
    apellidos           VARCHAR(100) NOT NULL,
    fecha_nacimiento    DATE         NOT NULL,
    sexo                CHAR(1)      NOT NULL CHECK (sexo IN ('M', 'F')),
    habitacion          VARCHAR(10),
    diagnostico_principal TEXT,
    nivel_movilidad     VARCHAR(20)  NOT NULL DEFAULT 'Autonomo'
                        CHECK (nivel_movilidad IN ('Autonomo', 'Asistido', 'Encamado')),
    contacto_emergencia VARCHAR(100),
    tel_emergencia      VARCHAR(15),
    fecha_ingreso       DATE         NOT NULL DEFAULT CURRENT_DATE,
    activo              BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_residente_edad CHECK (fecha_nacimiento <= CURRENT_DATE - INTERVAL '60 years')
);

-- N:M residente <-> staff (cuidadores y terapeutas asignados)
CREATE TABLE asignacion (
    id_asignacion   SERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL,
    id_staff        INT          NOT NULL,
    tipo_rol        VARCHAR(20)  NOT NULL CHECK (tipo_rol IN ('Cuidador', 'Terapeuta', 'Medico')),
    fecha_inicio    DATE         NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin       DATE,
    es_principal    BOOLEAN      NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_asignacion_fechas CHECK (fecha_fin IS NULL OR fecha_fin > fecha_inicio),
    CONSTRAINT fk_asignacion_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT fk_asignacion_staff FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE
);

CREATE INDEX idx_asignacion_residente ON asignacion (id_residente);
CREATE INDEX idx_asignacion_staff     ON asignacion (id_staff);


-- ============================================================
-- OPERACIONES CLINICAS Y DE CUIDADO
-- ============================================================

CREATE TABLE turno (
    id_turno        SERIAL PRIMARY KEY,
    id_staff        INT          NOT NULL,
    id_ala          INT          NOT NULL,
    fecha           DATE         NOT NULL,
    hora_inicio     TIME         NOT NULL,
    hora_fin        TIME         NOT NULL,
    CONSTRAINT ck_turno_horas CHECK (hora_fin > hora_inicio),
    CONSTRAINT fk_turno_staff FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE,
    CONSTRAINT fk_turno_ala FOREIGN KEY (id_ala)
        REFERENCES ala(id_ala) ON UPDATE CASCADE
);

CREATE INDEX idx_turno_staff ON turno (id_staff, fecha);
CREATE INDEX idx_turno_ala   ON turno (id_ala, fecha);

CREATE TABLE sesion_terapia (
    id_sesion       SERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL,
    id_terapeuta    INT          NOT NULL,
    id_sala         INT          NOT NULL,
    fecha_sesion    TIMESTAMP    NOT NULL,
    tipo_sesion     VARCHAR(20)  NOT NULL CHECK (tipo_sesion IN ('Individual', 'Grupal', 'Virtual')),
    duracion_min    INT          NOT NULL CHECK (duracion_min > 0 AND duracion_min <= 480),
    asistio         BOOLEAN      NOT NULL DEFAULT TRUE,
    notas           TEXT,
    CONSTRAINT fk_sesion_residente  FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT fk_sesion_terapeuta  FOREIGN KEY (id_terapeuta)
        REFERENCES staff(id_staff) ON UPDATE CASCADE,
    CONSTRAINT fk_sesion_sala       FOREIGN KEY (id_sala)
        REFERENCES sala(id_sala) ON UPDATE CASCADE
);

CREATE INDEX idx_sesion_residente ON sesion_terapia (id_residente);
CREATE INDEX idx_sesion_terapeuta ON sesion_terapia (id_terapeuta);
CREATE INDEX idx_sesion_fecha     ON sesion_terapia (fecha_sesion DESC);

CREATE TABLE checkin_estado_animo (
    id_checkin      SERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL,
    id_cuidador     INT          NOT NULL,
    fecha_registro  TIMESTAMP    NOT NULL DEFAULT NOW(),
    puntaje         INT          NOT NULL CHECK (puntaje BETWEEN 1 AND 5),
    notas           TEXT,
    CONSTRAINT fk_checkin_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT fk_checkin_cuidador  FOREIGN KEY (id_cuidador)
        REFERENCES staff(id_staff) ON UPDATE CASCADE
);

CREATE INDEX idx_checkin_residente ON checkin_estado_animo (id_residente, fecha_registro DESC);

CREATE TABLE reporte_incidente (
    id_incidente    SERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL,
    id_staff        INT          NOT NULL,
    fecha           TIMESTAMP    NOT NULL DEFAULT NOW(),
    tipo            VARCHAR(30)  NOT NULL
                    CHECK (tipo IN ('Caida', 'Agitacion', 'Deambulacion', 'Rechazo_Medicamento', 'Otro')),
    descripcion     TEXT         NOT NULL,
    severidad       VARCHAR(10)  NOT NULL CHECK (severidad IN ('Baja', 'Media', 'Alta')),
    CONSTRAINT fk_incidente_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT fk_incidente_staff     FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE
);

CREATE INDEX idx_incidente_residente ON reporte_incidente (id_residente);
CREATE INDEX idx_incidente_fecha      ON reporte_incidente (fecha DESC);


-- ============================================================
-- MEDICAMENTOS
-- ============================================================

CREATE TABLE horario_medicamento (
    id_horario      SERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL,
    id_medicamento  INT          NOT NULL,
    hora_programada TIME         NOT NULL,
    dosis           VARCHAR(30)  NOT NULL,
    frecuencia      VARCHAR(20)  NOT NULL
                    CHECK (frecuencia IN ('Diaria', 'Semanal', 'Mensual', 'Condicional')),
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_horario_residente   FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT fk_horario_medicamento FOREIGN KEY (id_medicamento)
        REFERENCES medicamento(id_medicamento) ON UPDATE CASCADE
);

CREATE INDEX idx_horario_residente ON horario_medicamento (id_residente);

CREATE TABLE log_medicamento (
    id_log                  SERIAL PRIMARY KEY,
    id_horario              INT          NOT NULL,
    id_cuidador             INT          NOT NULL,
    fecha_administracion    TIMESTAMP    NOT NULL DEFAULT NOW(),
    incidente               TEXT,
    CONSTRAINT fk_log_horario   FOREIGN KEY (id_horario)
        REFERENCES horario_medicamento(id_horario) ON UPDATE CASCADE,
    CONSTRAINT fk_log_cuidador  FOREIGN KEY (id_cuidador)
        REFERENCES staff(id_staff) ON UPDATE CASCADE
);

CREATE INDEX idx_log_medicamento_horario ON log_medicamento (id_horario);
CREATE INDEX idx_log_medicamento_fecha   ON log_medicamento (fecha_administracion DESC);


-- ============================================================
-- IOT
-- ============================================================

-- GPS — monitoreo exterior (jardin / patio)
CREATE TABLE gps_ping (
    id_ping         BIGSERIAL PRIMARY KEY,
    id_residente    INT           NOT NULL,
    latitud         DECIMAL(10,7) NOT NULL CHECK (latitud  BETWEEN -90  AND  90),
    longitud        DECIMAL(10,7) NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    registrado_en   TIMESTAMP     NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_gps_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE
);

CREATE INDEX idx_gps_residente ON gps_ping (id_residente, registrado_en DESC);

-- NFC — estaciones de medicamentos
CREATE TABLE nfc_tag (
    id_tag          SERIAL PRIMARY KEY,
    codigo_tag      VARCHAR(50)  NOT NULL,
    id_residente    INT          NOT NULL,
    descripcion     VARCHAR(100),
    CONSTRAINT uq_nfc_codigo UNIQUE (codigo_tag),
    CONSTRAINT fk_nfc_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE
);

CREATE TABLE nfc_evento (
    id_evento       BIGSERIAL PRIMARY KEY,
    id_tag          INT          NOT NULL,
    id_staff        INT          NOT NULL,
    escaneado_en    TIMESTAMP    NOT NULL DEFAULT NOW(),
    id_log_med      BIGINT,
    CONSTRAINT fk_nfc_evento_tag   FOREIGN KEY (id_tag)
        REFERENCES nfc_tag(id_tag) ON UPDATE CASCADE,
    CONSTRAINT fk_nfc_evento_staff FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE,
    CONSTRAINT fk_nfc_evento_log   FOREIGN KEY (id_log_med)
        REFERENCES log_medicamento(id_log) ON UPDATE CASCADE
);

CREATE INDEX idx_nfc_evento_tag ON nfc_evento (id_tag, escaneado_en DESC);

-- RFID — control de acceso a areas restringidas
CREATE TABLE lector_rfid (
    id_lector       SERIAL PRIMARY KEY,
    ubicacion       VARCHAR(100) NOT NULL,
    es_restringido  BOOLEAN      NOT NULL DEFAULT TRUE,
    id_ala          INT,
    id_sala         INT,
    CONSTRAINT fk_lector_ala  FOREIGN KEY (id_ala)
        REFERENCES ala(id_ala) ON UPDATE CASCADE,
    CONSTRAINT fk_lector_sala FOREIGN KEY (id_sala)
        REFERENCES sala(id_sala) ON UPDATE CASCADE
);

CREATE TABLE acceso_rfid (
    id_acceso           BIGSERIAL PRIMARY KEY,
    id_lector           INT          NOT NULL,
    id_staff            INT          NOT NULL,
    accedido_en         TIMESTAMP    NOT NULL DEFAULT NOW(),
    acceso_concedido    BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_acceso_lector FOREIGN KEY (id_lector)
        REFERENCES lector_rfid(id_lector) ON UPDATE CASCADE,
    CONSTRAINT fk_acceso_staff  FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE
);

CREATE INDEX idx_acceso_rfid_lector ON acceso_rfid (id_lector, accedido_en DESC);
CREATE INDEX idx_acceso_rfid_staff  ON acceso_rfid (id_staff, accedido_en DESC);

-- Beacon (BLE) — deteccion de presencia de staff por ala
CREATE TABLE beacon (
    id_beacon       SERIAL PRIMARY KEY,
    id_ala          INT          NOT NULL,
    nombre          VARCHAR(80)  NOT NULL,
    CONSTRAINT uq_beacon_nombre UNIQUE (nombre),
    CONSTRAINT fk_beacon_ala FOREIGN KEY (id_ala)
        REFERENCES ala(id_ala) ON UPDATE CASCADE
);

CREATE TABLE deteccion_beacon (
    id_deteccion    BIGSERIAL PRIMARY KEY,
    id_beacon       INT          NOT NULL,
    id_staff        INT          NOT NULL,
    detectado_en    TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_deteccion_beacon FOREIGN KEY (id_beacon)
        REFERENCES beacon(id_beacon) ON UPDATE CASCADE,
    CONSTRAINT fk_deteccion_staff  FOREIGN KEY (id_staff)
        REFERENCES staff(id_staff) ON UPDATE CASCADE
);

CREATE INDEX idx_deteccion_beacon ON deteccion_beacon (id_beacon, detectado_en DESC);
CREATE INDEX idx_deteccion_staff  ON deteccion_beacon (id_staff, detectado_en DESC);


-- ============================================================
-- AUDITORIA
-- ============================================================

CREATE TABLE log_auditoria (
    id_log              BIGSERIAL PRIMARY KEY,
    id_usuario          INT          NOT NULL,
    tabla_afectada      VARCHAR(80)  NOT NULL,
    operacion           VARCHAR(10)  NOT NULL CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    id_registro         INT,
    ip_origen           VARCHAR(45),
    timestamp_operacion TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_log_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario_sistema(id_usuario) ON UPDATE CASCADE
);

CREATE INDEX idx_log_usuario    ON log_auditoria (id_usuario);
CREATE INDEX idx_log_timestamp  ON log_auditoria (timestamp_operacion DESC);
