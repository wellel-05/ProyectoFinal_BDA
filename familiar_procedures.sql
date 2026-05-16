-- Stored procedures para el portal familiar

CREATE OR REPLACE PROCEDURE sp_auth_familiar(p_username VARCHAR, p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT uf.id_usuario, uf.password_hash, uf.activo,
           f.id_familiar, f.nombre, f.apellidos, f.email
    FROM usuario_familiar uf
    JOIN familiar f ON uf.id_familiar = f.id_familiar
    WHERE uf.username = p_username AND uf.activo = TRUE AND f.activo = TRUE;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_residentes_del_familiar(p_id_familiar INT, p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT r.id_residente,
           r.nombre || ' ' || r.apellidos AS residente,
           r.habitacion,
           r.diagnostico_principal,
           EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT AS edad,
           fr.parentesco,
           fr.es_contacto_principal,
           c.puntaje AS ultimo_puntaje_animo
    FROM familiar_residente fr
    JOIN residente r ON fr.id_residente = r.id_residente
    LEFT JOIN LATERAL (
        SELECT puntaje FROM checkin_estado_animo
        WHERE id_residente = r.id_residente
        ORDER BY fecha_registro DESC LIMIT 1
    ) c ON TRUE
    WHERE fr.id_familiar = p_id_familiar
      AND fr.fecha_fin IS NULL
      AND r.activo = TRUE
    ORDER BY fr.es_contacto_principal DESC, r.apellidos;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_lista_familiares(p_cursor REFCURSOR)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT f.id_familiar,
           f.nombre || ' ' || f.apellidos AS familiar,
           f.email, f.telefono, f.activo, f.fecha_registro,
           COUNT(fr.id_residente) AS residentes_vinculados,
           uf.username
    FROM familiar f
    LEFT JOIN familiar_residente fr ON fr.id_familiar = f.id_familiar AND fr.fecha_fin IS NULL
    LEFT JOIN usuario_familiar uf   ON uf.id_familiar = f.id_familiar
    GROUP BY f.id_familiar, f.nombre, f.apellidos, f.email,
             f.telefono, f.activo, f.fecha_registro, uf.username
    ORDER BY f.activo DESC, f.apellidos;
END;
$$;

-- Devuelve el plan activo y estadísticas de pagos de un residente
CREATE OR REPLACE PROCEDURE sp_plan_residente(
    p_id_residente INT,
    p_id_familiar  INT,
    p_cursor       REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT pr.id_plan,
           pr.tipo_plan,
           pr.monto_mensual,
           pr.fecha_inicio,
           COALESCE(stats.total_pagado,  0) AS total_pagado,
           COALESCE(stats.num_pagos,     0) AS num_pagos,
           p_ult.fecha_pago                  AS ultimo_pago,
           p_ult.metodo_pago                 AS ultimo_metodo,
           -- Indica si el mes actual ya fue pagado por este familiar
           EXISTS (
               SELECT 1 FROM pago
               WHERE id_residente = p_id_residente
                 AND id_familiar  = p_id_familiar
                 AND periodo_mes  = EXTRACT(MONTH FROM CURRENT_DATE)::INT
                 AND periodo_anio = EXTRACT(YEAR  FROM CURRENT_DATE)::INT
                 AND estado       = 'Completado'
           ) AS mes_actual_pagado
    FROM plan_residente pr
    LEFT JOIN (
        SELECT id_plan,
               SUM(monto)  AS total_pagado,
               COUNT(*)    AS num_pagos
        FROM pago WHERE estado = 'Completado'
        GROUP BY id_plan
    ) stats ON stats.id_plan = pr.id_plan
    LEFT JOIN LATERAL (
        SELECT fecha_pago, metodo_pago
        FROM pago
        WHERE id_plan    = pr.id_plan
          AND id_familiar = p_id_familiar
          AND estado      = 'Completado'
        ORDER BY fecha_pago DESC LIMIT 1
    ) p_ult ON TRUE
    WHERE pr.id_residente = p_id_residente
      AND pr.activo = TRUE
    LIMIT 1;
END;
$$;

-- Historial de pagos de un residente para un familiar
CREATE OR REPLACE PROCEDURE sp_pagos_residente(
    p_id_residente INT,
    p_id_familiar  INT,
    p_cursor       REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT p.id_pago,
           p.monto,
           p.fecha_pago,
           p.metodo_pago,
           p.referencia,
           p.estado,
           p.periodo_mes,
           p.periodo_anio,
           p.concepto,
           pr.tipo_plan
    FROM pago p
    JOIN plan_residente pr ON pr.id_plan = p.id_plan
    WHERE p.id_residente = p_id_residente
      AND p.id_familiar  = p_id_familiar
    ORDER BY p.fecha_pago DESC
    LIMIT 24;
END;
$$;

-- Registrar un pago simulado
CREATE OR REPLACE PROCEDURE sp_registrar_pago(
    p_id_familiar  INT,
    p_id_residente INT,
    p_metodo_pago  VARCHAR,
    p_periodo_mes  INT,
    p_periodo_anio INT,
    OUT p_ok       INT,
    OUT p_msg      TEXT,
    OUT p_referencia VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_plan   INT;
    v_monto     DECIMAL(10,2);
    v_tipo_plan VARCHAR(20);
    v_concepto  VARCHAR(150);
BEGIN
    -- Verificar que el familiar tiene acceso al residente
    IF NOT EXISTS (
        SELECT 1 FROM familiar_residente
        WHERE id_familiar = p_id_familiar AND id_residente = p_id_residente
          AND fecha_fin IS NULL
    ) THEN
        p_ok  := 0;
        p_msg := 'No tienes acceso a este residente.';
        p_referencia := NULL;
        RETURN;
    END IF;

    -- Verificar que no esté duplicado
    IF EXISTS (
        SELECT 1 FROM pago
        WHERE id_familiar  = p_id_familiar
          AND id_residente = p_id_residente
          AND periodo_mes  = p_periodo_mes
          AND periodo_anio = p_periodo_anio
          AND estado       = 'Completado'
    ) THEN
        p_ok  := 0;
        p_msg := 'Ya existe un pago completado para ese periodo.';
        p_referencia := NULL;
        RETURN;
    END IF;

    -- Obtener plan activo
    SELECT id_plan, monto_mensual, tipo_plan
    INTO v_id_plan, v_monto, v_tipo_plan
    FROM plan_residente
    WHERE id_residente = p_id_residente AND activo = TRUE
    LIMIT 1;

    IF v_id_plan IS NULL THEN
        p_ok  := 0;
        p_msg := 'El residente no tiene un plan activo asignado.';
        p_referencia := NULL;
        RETURN;
    END IF;

    -- Generar referencia única
    p_referencia := UPPER(
        CASE p_metodo_pago
            WHEN 'Transferencia SPEI' THEN 'SPEI'
            WHEN 'OXXO Pay'           THEN 'OXXO'
            ELSE                           'CARD'
        END
        || TO_CHAR(NOW(), 'YYYYMMDD')
        || LPAD(FLOOR(RANDOM() * 9999)::TEXT, 4, '0')
    );

    v_concepto := 'Mensualidad Plan ' || v_tipo_plan || ' — '
        || TO_CHAR(TO_DATE(p_periodo_anio::TEXT || '-' || p_periodo_mes::TEXT || '-01', 'YYYY-MM-DD'), 'TMMonth YYYY');

    INSERT INTO pago (id_familiar, id_residente, id_plan, monto, metodo_pago,
                      referencia, estado, periodo_mes, periodo_anio, concepto)
    VALUES (p_id_familiar, p_id_residente, v_id_plan, v_monto, p_metodo_pago,
            p_referencia, 'Completado', p_periodo_mes, p_periodo_anio, v_concepto);

    p_ok  := 1;
    p_msg := 'Pago de $' || TO_CHAR(v_monto, 'FM999,999,990.00')
          || ' MXN registrado correctamente. Referencia: ' || p_referencia;
EXCEPTION
    WHEN OTHERS THEN
        p_ok  := 0;
        p_msg := 'Error al registrar el pago: ' || SQLERRM;
        p_referencia := NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_registrar_familiar(
    p_nombre       VARCHAR,
    p_apellidos    VARCHAR,
    p_parentesco   VARCHAR,
    p_email        VARCHAR,
    p_telefono     VARCHAR,
    p_id_residente INT,
    p_username     VARCHAR,
    p_password_hash VARCHAR,
    p_es_principal BOOLEAN,
    OUT p_ok  INT,
    OUT p_msg TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id INT;
BEGIN
    INSERT INTO familiar (nombre, apellidos, email, telefono)
    VALUES (p_nombre, p_apellidos, p_email, p_telefono)
    RETURNING id_familiar INTO v_id;

    INSERT INTO familiar_residente (id_familiar, id_residente, parentesco, es_contacto_principal)
    VALUES (v_id, p_id_residente, p_parentesco, p_es_principal);

    INSERT INTO usuario_familiar (username, password_hash, id_familiar)
    VALUES (p_username, p_password_hash, v_id);

    p_ok  := 1;
    p_msg := 'Familiar registrado correctamente.';
EXCEPTION
    WHEN unique_violation THEN
        p_ok  := 0;
        p_msg := 'El email o nombre de usuario ya existe en el sistema.';
    WHEN OTHERS THEN
        p_ok  := 0;
        p_msg := 'Error: ' || SQLERRM;
END;
$$;
