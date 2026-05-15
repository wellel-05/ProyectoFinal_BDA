-- ============================================================
--  PORTAL FAMILIAR — DDL adicional
--  Ejecutar después de DDL.sql
-- ============================================================

-- Tabla de familiares / contactos de residentes
CREATE TABLE IF NOT EXISTS familiar (
    id_familiar     SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    apellidos       VARCHAR(100) NOT NULL,
    email           VARCHAR(100) NOT NULL,
    telefono        VARCHAR(15),
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_registro  DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_familiar_email UNIQUE (email)
);

-- Vínculo N:M familiar <-> residente (un familiar puede estar vinculado
-- a varios residentes con distinto parentesco)
CREATE TABLE IF NOT EXISTS familiar_residente (
    id_vinculo          SERIAL PRIMARY KEY,
    id_familiar         INT          NOT NULL,
    id_residente        INT          NOT NULL,
    parentesco          VARCHAR(50)  NOT NULL DEFAULT 'Familiar',
    es_contacto_principal BOOLEAN    NOT NULL DEFAULT FALSE,
    fecha_inicio        DATE         NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin           DATE,
    CONSTRAINT fk_vinculo_familiar   FOREIGN KEY (id_familiar)
        REFERENCES familiar(id_familiar)   ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_vinculo_residente  FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT uq_vinculo UNIQUE (id_familiar, id_residente),
    CONSTRAINT ck_vinculo_fechas CHECK (fecha_fin IS NULL OR fecha_fin > fecha_inicio)
);

CREATE INDEX IF NOT EXISTS idx_vinculo_familiar   ON familiar_residente (id_familiar);
CREATE INDEX IF NOT EXISTS idx_vinculo_residente  ON familiar_residente (id_residente);

-- Cuentas de acceso para familiares (independiente de usuario_sistema)
CREATE TABLE IF NOT EXISTS usuario_familiar (
    id_usuario      SERIAL PRIMARY KEY,
    username        VARCHAR(50)  NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    id_familiar     INT          NOT NULL,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_login    TIMESTAMP,
    CONSTRAINT uq_usuario_familiar_username UNIQUE (username),
    CONSTRAINT fk_usuario_familiar FOREIGN KEY (id_familiar)
        REFERENCES familiar(id_familiar) ON UPDATE CASCADE ON DELETE CASCADE
);

-- ── Seed de demostración ───────────────────────────────────────────────────
-- Insertar un familiar de prueba vinculado al residente 1
INSERT INTO familiar (nombre, apellidos, email, telefono)
VALUES ('Maria', 'Lopez Garcia', 'maria.lopez@familiar.com', '8112345678')
ON CONFLICT (email) DO NOTHING;

INSERT INTO familiar_residente (id_familiar, id_residente, parentesco, es_contacto_principal)
SELECT f.id_familiar, 1, 'Hija', TRUE
FROM familiar f
WHERE f.email = 'maria.lopez@familiar.com'
ON CONFLICT (id_familiar, id_residente) DO NOTHING;

-- Contraseña: familiar123  (hash werkzeug scrypt)
INSERT INTO usuario_familiar (username, password_hash, id_familiar)
SELECT 'familiar1',
       'scrypt:32768:8:1$salt12345678901234$c2NyeXB0OjMyNzY4OjA4OjE$dummyhash',
       f.id_familiar
FROM familiar f
WHERE f.email = 'maria.lopez@familiar.com'
ON CONFLICT (username) DO NOTHING;
