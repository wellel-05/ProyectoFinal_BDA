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

-- ── Módulo de pagos y planes ──────────────────────────────────────────────

-- Plan contratado por residente (Esencial / Bienestar / Premium)
CREATE TABLE IF NOT EXISTS plan_residente (
    id_plan         SERIAL PRIMARY KEY,
    id_residente    INT          NOT NULL,
    tipo_plan       VARCHAR(20)  NOT NULL CHECK (tipo_plan IN ('Esencial', 'Bienestar', 'Premium')),
    monto_mensual   DECIMAL(10,2) NOT NULL,
    fecha_inicio    DATE         NOT NULL DEFAULT CURRENT_DATE,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_plan_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT uq_plan_activo_residente UNIQUE (id_residente, activo)
        DEFERRABLE INITIALLY DEFERRED
);

-- Historial de pagos simulados
CREATE TABLE IF NOT EXISTS pago (
    id_pago         SERIAL PRIMARY KEY,
    id_familiar     INT          NOT NULL,
    id_residente    INT          NOT NULL,
    id_plan         INT          NOT NULL,
    monto           DECIMAL(10,2) NOT NULL CHECK (monto > 0),
    fecha_pago      TIMESTAMP    NOT NULL DEFAULT NOW(),
    metodo_pago     VARCHAR(25)  NOT NULL
                    CHECK (metodo_pago IN ('Tarjeta de crédito', 'Transferencia SPEI', 'OXXO Pay')),
    referencia      VARCHAR(30)  NOT NULL,
    estado          VARCHAR(15)  NOT NULL DEFAULT 'Completado'
                    CHECK (estado IN ('Completado', 'Pendiente', 'Rechazado')),
    periodo_mes     INT          NOT NULL CHECK (periodo_mes BETWEEN 1 AND 12),
    periodo_anio    INT          NOT NULL CHECK (periodo_anio >= 2020),
    concepto        VARCHAR(150),
    CONSTRAINT fk_pago_familiar  FOREIGN KEY (id_familiar)
        REFERENCES familiar(id_familiar)  ON UPDATE CASCADE,
    CONSTRAINT fk_pago_residente FOREIGN KEY (id_residente)
        REFERENCES residente(id_residente) ON UPDATE CASCADE,
    CONSTRAINT fk_pago_plan      FOREIGN KEY (id_plan)
        REFERENCES plan_residente(id_plan) ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_pago_familiar  ON pago (id_familiar, fecha_pago DESC);
CREATE INDEX IF NOT EXISTS idx_pago_residente ON pago (id_residente, fecha_pago DESC);

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

-- Contraseña: familiar123  (hash werkzeug scrypt generado con generate_password_hash)
INSERT INTO usuario_familiar (username, password_hash, id_familiar)
SELECT 'familiar1',
       'scrypt:32768:8:1$mNrfhGCK6TJbBTCj$2d57d6db36438698fee16613fd251a680ce53b9a415608509890a82cff5e38e71358f7e79ebc8a94d8c68a101f7f933539815e2126a68d5e907fbfa17ab608f0',
       f.id_familiar
FROM familiar f
WHERE f.email = 'maria.lopez@familiar.com'
ON CONFLICT (username) DO NOTHING;

-- Planes demo para los 3 residentes vinculados a familiares
INSERT INTO plan_residente (id_residente, tipo_plan, monto_mensual, fecha_inicio)
VALUES
    (1, 'Bienestar', 38000.00, '2024-03-01'),
    (2, 'Premium',   55000.00, '2024-01-15'),
    (3, 'Esencial',  22500.00, '2024-06-01')
ON CONFLICT (id_residente, activo) DO NOTHING;

-- Historial de pagos demo (últimos 4 meses para residente 1)
INSERT INTO pago (id_familiar, id_residente, id_plan, monto, fecha_pago,
                  metodo_pago, referencia, estado, periodo_mes, periodo_anio, concepto)
SELECT
    f.id_familiar, 1,
    (SELECT id_plan FROM plan_residente WHERE id_residente = 1 AND activo = TRUE LIMIT 1),
    38000.00, gen_fecha, metodo, ref, 'Completado', mes, anio,
    'Mensualidad Plan Bienestar — ' || TO_CHAR(gen_fecha, 'Mon YYYY')
FROM familiar f
CROSS JOIN (VALUES
    (NOW() - INTERVAL '3 months', 'Transferencia SPEI', 'SPEI20250201', 2, 2025),
    (NOW() - INTERVAL '2 months', 'Tarjeta de crédito', 'CARD20250301', 3, 2025),
    (NOW() - INTERVAL '1 month',  'Transferencia SPEI', 'SPEI20250401', 4, 2025),
    (NOW() - INTERVAL '5 days',   'OXXO Pay',           'OXXO20250501', 5, 2025)
) AS t(gen_fecha, metodo, ref, mes, anio)
WHERE f.email = 'maria.lopez@familiar.com'
ON CONFLICT DO NOTHING;
