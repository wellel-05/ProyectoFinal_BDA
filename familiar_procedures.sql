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
