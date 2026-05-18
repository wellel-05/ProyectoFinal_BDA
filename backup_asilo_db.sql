--
-- PostgreSQL database dump
--

\restrict 8igI99TvM6iruaxktGaacONYzt4xpGsD0iJRpRfc1Umv2ae0GACvRfrQsXtTkuw

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: sp_accesos_no_autorizados(date, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_accesos_no_autorizados(IN p_fecha date, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_actualizar_incidente(integer, character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_actualizar_incidente(IN p_id_incidente integer, IN p_tipo character varying, IN p_descripcion text, IN p_severidad character varying, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_actualizar_medicamento(integer, character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_actualizar_medicamento(IN p_id integer, IN p_nombre character varying, IN p_descripcion text, IN p_unidad character varying, OUT p_ok boolean, OUT p_msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_actualizar_residente(integer, character varying, text, character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_actualizar_residente(IN p_id_residente integer, IN p_habitacion character varying, IN p_diagnostico text, IN p_nivel_movilidad character varying, IN p_contacto character varying, IN p_tel_contacto character varying, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_actualizar_sesion(integer, boolean, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_actualizar_sesion(IN p_id_sesion integer, IN p_asistio boolean, IN p_notas text, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_actualizar_staff(integer, character varying, character varying, character varying, character varying, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_actualizar_staff(IN p_id_staff integer, IN p_nombre character varying, IN p_apellidos character varying, IN p_especialidad character varying, IN p_email character varying, IN p_id_rol integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_actualizar_ultimo_login(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_actualizar_ultimo_login(IN p_id_usuario integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE usuario_sistema SET ultimo_login = NOW() WHERE id_usuario = p_id_usuario;
    ok := 1; msg := 'Login registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := SQLERRM;
END;
$$;


--
-- Name: sp_adherencia_terapeutica(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_adherencia_terapeutica(IN p_dias integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_animo_bajo_cuidador(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_animo_bajo_cuidador(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_asignaciones_residente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_asignaciones_residente(IN p_id_residente integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_auth_familiar(character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_auth_familiar(IN p_username character varying, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT uf.id_usuario, uf.password_hash, uf.activo,
           f.id_familiar, f.nombre, f.apellidos, f.email
    FROM usuario_familiar uf
    JOIN familiar f ON uf.id_familiar = f.id_familiar
    WHERE uf.username = p_username AND uf.activo = TRUE AND f.activo = TRUE;
END;
$$;


--
-- Name: sp_auth_usuario(text, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_auth_usuario(IN p_username text, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT u.id_usuario, u.username, u.password_hash,
               s.id_staff, s.nombre, s.apellidos, s.especialidad,
               r.nivel_acceso, r.nombre_rol
        FROM usuario_sistema u
        JOIN staff s ON u.id_staff = s.id_staff
        JOIN rol   r ON s.id_rol   = r.id_rol
        WHERE u.username = p_username
          AND u.activo   = TRUE
          AND s.activo   = TRUE;
END;
$$;


--
-- Name: sp_cambiar_cuidador(integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_cambiar_cuidador(IN p_id_residente integer, IN p_id_nuevo_cuidador integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_carga_operativa(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_carga_operativa(IN p_dias integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_checkin_estado_animo(integer, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_checkin_estado_animo(IN p_id_residente integer, IN p_id_cuidador integer, IN p_puntaje integer, IN p_notas text, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO checkin_estado_animo (id_residente, id_cuidador, puntaje, notas)
    VALUES (p_id_residente, p_id_cuidador, p_puntaje, p_notas);
    ok := 1; msg := 'Check-in registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


--
-- Name: sp_crear_incidente_automatico(integer, integer, character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_crear_incidente_automatico(IN p_id_residente integer, IN p_id_staff integer, IN p_tipo character varying, IN p_descripcion text, IN p_severidad character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO reporte_incidente (id_residente, id_staff, tipo, descripcion, severidad)
    VALUES (p_id_residente, p_id_staff, p_tipo, p_descripcion, p_severidad);
END;
$$;


--
-- Name: sp_dar_baja_residente(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_dar_baja_residente(IN p_id_residente integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_dashboard_admin(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_dashboard_admin(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_dashboard_cuidador(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_dashboard_cuidador(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_dashboard_terapeuta(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_dashboard_terapeuta(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_detalle_residente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_detalle_residente(IN p_id_residente integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT r.*,
               EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT AS edad,
               TO_CHAR(r.fecha_ingreso, 'DD Mon YYYY') AS fecha_ingreso
        FROM residente r
        WHERE r.id_residente = p_id_residente;
END;
$$;


--
-- Name: sp_eliminar_medicamento(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_eliminar_medicamento(IN p_id integer, OUT p_ok boolean, OUT p_msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_eliminar_sesion(integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_eliminar_sesion(IN p_id_sesion integer, IN p_id_terapeuta integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_eliminar_turno(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_eliminar_turno(IN p_id integer, OUT p_ok boolean, OUT p_msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_evolucion_animo_global(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_evolucion_animo_global(IN p_dias integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_evolucion_animo_residente(integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_evolucion_animo_residente(IN p_id_residente integer, IN p_dias integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_historial_checkins_residente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_historial_checkins_residente(IN p_id_residente integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT c.*, s.nombre || ' ' || s.apellidos AS cuidador
        FROM checkin_estado_animo c
        JOIN staff s ON c.id_cuidador = s.id_staff
        WHERE c.id_residente = p_id_residente
        ORDER BY c.fecha_registro DESC
        LIMIT 10;
END;
$$;


--
-- Name: sp_historial_incidentes_residente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_historial_incidentes_residente(IN p_id_residente integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT ri.*, s.nombre || ' ' || s.apellidos AS reportado_por,
               TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha
        FROM reporte_incidente ri
        JOIN staff s ON ri.id_staff = s.id_staff
        WHERE ri.id_residente = p_id_residente
        ORDER BY ri.fecha DESC
        LIMIT 5;
END;
$$;


--
-- Name: sp_historial_sesiones_residente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_historial_sesiones_residente(IN p_id_residente integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, s.nombre || ' ' || s.apellidos AS terapeuta, sa.nombre AS sala
        FROM sesion_terapia st
        JOIN staff s  ON st.id_terapeuta = s.id_staff
        JOIN sala  sa ON st.id_sala      = sa.id_sala
        WHERE st.id_residente = p_id_residente
        ORDER BY st.fecha_sesion DESC
        LIMIT 10;
END;
$$;


--
-- Name: sp_ids_residentes_cuidador(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_ids_residentes_cuidador(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT a.id_residente
    FROM asignacion a
    WHERE a.id_staff  = p_id_staff
      AND a.tipo_rol  = 'Cuidador'
      AND a.fecha_fin IS NULL;
END;
$$;


--
-- Name: sp_incidentes_por_severidad(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_incidentes_por_severidad(IN p_dias integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_incidentes_residente_lista(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_incidentes_residente_lista(IN p_id_residente integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT ri.*, s.nombre || ' ' || s.apellidos AS reportado_por,
               TO_CHAR(ri.fecha, 'DD Mon YYYY') AS fecha
        FROM reporte_incidente ri
        JOIN staff s ON ri.id_staff = s.id_staff
        WHERE ri.id_residente = p_id_residente
        ORDER BY ri.fecha DESC;
END;
$$;


--
-- Name: sp_lectores_rfid(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lectores_rfid(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_limite_jardin(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_limite_jardin(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT * FROM limite_jardin LIMIT 1;
END;
$$;


--
-- Name: sp_lista_alas(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_alas(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_ala, nombre, piso FROM ala WHERE activa = TRUE ORDER BY piso, nombre;
END;
$$;


--
-- Name: sp_lista_cuidadores(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_cuidadores(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_lista_familiares(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_familiares(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_lista_horarios_medicamento(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_horarios_medicamento(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_lista_medicamentos(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_medicamentos(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_medicamento, nombre, descripcion, unidad
    FROM medicamento
    ORDER BY nombre;
END;
$$;


--
-- Name: sp_lista_residentes_activos(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_residentes_activos(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_lista_roles(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_roles(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_cursor FOR
    SELECT id_rol, nombre_rol, nivel_acceso
    FROM rol
    ORDER BY nivel_acceso;
END;
$$;


--
-- Name: sp_lista_staff(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_staff(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_lista_staff_activo(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_staff_activo(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_lista_turnos(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_lista_turnos(IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_log_acceso_rfid(date, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_log_acceso_rfid(IN p_fecha date, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_log_auditoria(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_log_auditoria(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT l.*, u.username, s.nombre || ' ' || s.apellidos AS usuario_nombre,
               TO_CHAR(l.timestamp_operacion, 'DD Mon YYYY HH12:MI AM') AS fecha_hora
        FROM log_auditoria l
        JOIN usuario_sistema u ON l.id_usuario = u.id_usuario
        JOIN staff s ON u.id_staff = s.id_staff
        ORDER BY l.timestamp_operacion DESC
        LIMIT 200;
END;
$$;


--
-- Name: sp_log_medicamento_nfc(character varying, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_log_medicamento_nfc(IN p_codigo_tag character varying, IN p_id_staff integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_log_nfc_hoy(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_log_nfc_hoy(IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT TO_CHAR(ne.escaneado_en, 'HH12:MI AM') AS hora,
               nt.descripcion AS medicamento,
               r.nombre || ' ' || r.apellidos AS residente
        FROM nfc_evento ne
        JOIN nfc_tag nt  ON ne.id_tag       = nt.id_tag
        JOIN residente r ON nt.id_residente = r.id_residente
        WHERE ne.id_staff = p_id_staff
          AND ne.escaneado_en::DATE = CURRENT_DATE
        ORDER BY ne.escaneado_en DESC
        LIMIT 10;
END;
$$;


--
-- Name: sp_medicamentos_admin_hoy(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_medicamentos_admin_hoy(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_meds_pendientes_cuidador(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_meds_pendientes_cuidador(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_pagos_residente(integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_pagos_residente(IN p_id_residente integer, IN p_id_familiar integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_plan_residente(integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_plan_residente(IN p_id_residente integer, IN p_id_familiar integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_registrar_acceso_rfid(integer, integer, boolean); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_acceso_rfid(IN p_id_lector integer, IN p_id_staff integer, IN p_acceso_concedido boolean, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO acceso_rfid (id_lector, id_staff, acceso_concedido)
    VALUES (p_id_lector, p_id_staff, COALESCE(p_acceso_concedido, TRUE));
    ok := 1; msg := 'Acceso registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


--
-- Name: sp_registrar_auditoria(integer, character varying, character varying, integer, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_auditoria(IN p_id_usuario integer, IN p_tabla character varying, IN p_operacion character varying, IN p_id_registro integer, IN p_ip character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro, ip_origen)
    VALUES (p_id_usuario, p_tabla, p_operacion, p_id_registro, p_ip);
END;
$$;


--
-- Name: sp_registrar_familiar(character varying, character varying, character varying, character varying, character varying, integer, character varying, character varying, boolean); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_familiar(IN p_nombre character varying, IN p_apellidos character varying, IN p_parentesco character varying, IN p_email character varying, IN p_telefono character varying, IN p_id_residente integer, IN p_username character varying, IN p_password_hash character varying, IN p_es_principal boolean, OUT p_ok integer, OUT p_msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_registrar_horario_medicamento(integer, integer, time without time zone, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_horario_medicamento(IN p_id_residente integer, IN p_id_medicamento integer, IN p_hora time without time zone, IN p_dosis character varying, IN p_frecuencia character varying, OUT p_ok boolean, OUT p_msg text, OUT p_id_horario integer)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_registrar_incidente(integer, integer, character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_incidente(IN p_id_residente integer, IN p_id_staff integer, IN p_tipo character varying, IN p_descripcion text, IN p_severidad character varying, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO reporte_incidente (id_residente, id_staff, tipo, descripcion, severidad)
    VALUES (p_id_residente, p_id_staff, p_tipo, p_descripcion, p_severidad);
    ok := 1; msg := 'Incidente registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


--
-- Name: sp_registrar_medicamento(character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_medicamento(IN p_nombre character varying, IN p_descripcion text, IN p_unidad character varying, OUT p_ok boolean, OUT p_msg text, OUT p_id integer)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_registrar_pago(integer, integer, character varying, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_pago(IN p_id_familiar integer, IN p_id_residente integer, IN p_metodo_pago character varying, IN p_periodo_mes integer, IN p_periodo_anio integer, OUT p_ok integer, OUT p_msg text, OUT p_referencia character varying)
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- Name: sp_registrar_residente(character varying, character varying, date, character, character varying, text, character varying, character varying, character varying, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_residente(IN p_nombre character varying, IN p_apellidos character varying, IN p_fecha_nacimiento date, IN p_sexo character, IN p_habitacion character varying, IN p_diagnostico text, IN p_nivel_movilidad character varying, IN p_contacto character varying, IN p_tel_contacto character varying, IN p_id_cuidador integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_registrar_staff(character varying, character varying, character varying, character varying, integer, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_staff(IN p_nombre character varying, IN p_apellidos character varying, IN p_especialidad character varying, IN p_email character varying, IN p_id_rol integer, IN p_username character varying, IN p_password_hash character varying, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_registrar_turno(integer, integer, date, time without time zone, time without time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_registrar_turno(IN p_id_staff integer, IN p_id_ala integer, IN p_fecha date, IN p_hora_inicio time without time zone, IN p_hora_fin time without time zone, OUT p_ok boolean, OUT p_msg text, OUT p_id integer)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_reservar_sesion(integer, integer, integer, timestamp without time zone, integer, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_reservar_sesion(IN p_id_residente integer, IN p_id_terapeuta integer, IN p_id_sala integer, IN p_fecha_sesion timestamp without time zone, IN p_duracion_min integer, IN p_tipo_sesion character varying, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_residentes_al_aire_libre(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_residentes_al_aire_libre(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_residentes_asignados_terapeuta(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_residentes_asignados_terapeuta(IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT vr.*,
               (SELECT COUNT(*) FROM sesion_terapia st
                WHERE st.id_residente = vr.id_residente
                  AND st.id_terapeuta = p_id_staff)::INT AS total_sesiones
        FROM v_residentes_resumen vr
        WHERE EXISTS (
            SELECT 1 FROM asignacion a
            WHERE a.id_residente = vr.id_residente
              AND a.id_staff = p_id_staff AND a.fecha_fin IS NULL
        );
END;
$$;


--
-- Name: sp_residentes_cuidador_lista(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_residentes_cuidador_lista(IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion
        FROM residente r
        JOIN asignacion a ON a.id_residente = r.id_residente
        WHERE a.id_staff = p_id_staff AND a.tipo_rol = 'Cuidador'
          AND a.fecha_fin IS NULL AND r.activo = TRUE
        ORDER BY r.apellidos;
END;
$$;


--
-- Name: sp_residentes_cuidador_vista(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_residentes_cuidador_vista(IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT vr.*
        FROM v_residentes_resumen vr
        WHERE EXISTS (
            SELECT 1 FROM asignacion a
            WHERE a.id_residente = vr.id_residente
              AND a.id_staff   = p_id_staff
              AND a.tipo_rol   = 'Cuidador'
              AND a.fecha_fin IS NULL
        );
END;
$$;


--
-- Name: sp_residentes_del_familiar(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_residentes_del_familiar(IN p_id_familiar integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_residentes_sesion_nueva(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_residentes_sesion_nueva(IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion
        FROM residente r
        JOIN asignacion a ON a.id_residente = r.id_residente
        WHERE a.id_staff = p_id_staff AND a.fecha_fin IS NULL AND r.activo = TRUE
        ORDER BY r.apellidos;
END;
$$;


--
-- Name: sp_resumen_iot(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_resumen_iot(IN p_dias integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_resumen_semanal_cuidador(date, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_resumen_semanal_cuidador(IN p_semana_inicio date, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_salas(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_salas(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT s.*, a.nombre AS ala
        FROM sala s
        LEFT JOIN ala a ON s.id_ala = a.id_ala
        ORDER BY s.nombre;
END;
$$;


--
-- Name: sp_sesiones_hoy_terapeuta(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_sesiones_hoy_terapeuta(IN p_id_staff integer, IN p_cursor refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_sesiones_residente_terapeuta(integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_sesiones_residente_terapeuta(IN p_id_residente integer, IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, sa.nombre AS sala
        FROM sesion_terapia st
        JOIN sala sa ON st.id_sala = sa.id_sala
        WHERE st.id_residente = p_id_residente AND st.id_terapeuta = p_id_staff
        ORDER BY st.fecha_sesion DESC;
END;
$$;


--
-- Name: sp_sesiones_terapeuta(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_sesiones_terapeuta(IN p_id_staff integer, INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, r.nombre || ' ' || r.apellidos AS residente, sa.nombre AS sala,
               TO_CHAR(st.fecha_sesion, 'DD Mon YYYY HH12:MI AM') AS fecha_sesion_fmt
        FROM sesion_terapia st
        JOIN residente r ON st.id_residente = r.id_residente
        JOIN sala sa     ON st.id_sala      = sa.id_sala
        WHERE st.id_terapeuta = p_id_staff
        ORDER BY st.fecha_sesion DESC;
END;
$$;


--
-- Name: sp_tags_nfc(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_tags_nfc(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT DISTINCT ON (nt.id_tag)
               nt.id_tag, nt.codigo_tag, nt.descripcion,
               r.nombre || ' ' || r.apellidos AS residente, r.habitacion,
               COALESCE(m.nombre, nt.descripcion) AS medicamento
        FROM nfc_tag nt
        JOIN residente r ON nt.id_residente = r.id_residente
        LEFT JOIN horario_medicamento hm ON hm.id_residente   = nt.id_residente
        LEFT JOIN medicamento m          ON hm.id_medicamento = m.id_medicamento
        ORDER BY nt.id_tag, r.habitacion;
END;
$$;


--
-- Name: sp_todos_incidentes(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_todos_incidentes(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN resultado FOR
        SELECT ri.*, r.nombre || ' ' || r.apellidos AS residente,
               s.nombre || ' ' || s.apellidos AS reportado_por,
               TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha
        FROM reporte_incidente ri
        JOIN residente r ON ri.id_residente = r.id_residente
        JOIN staff s     ON ri.id_staff     = s.id_staff
        ORDER BY ri.fecha DESC;
END;
$$;


--
-- Name: sp_toggle_horario_medicamento(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_toggle_horario_medicamento(IN p_id_horario integer, OUT p_ok boolean, OUT p_msg text, OUT p_activo boolean)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_toggle_staff(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_toggle_staff(IN p_id_staff integer, OUT ok integer, OUT msg text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sp_ubicacion_actual_staff(refcursor); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_ubicacion_actual_staff(INOUT resultado refcursor)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_alerta_animo_bajo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_alerta_animo_bajo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_alerta_gps_fuera_limite(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_alerta_gps_fuera_limite() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_auditoria_acceso_rfid(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_auditoria_acceso_rfid() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_auditoria_residente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_auditoria_residente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_auditoria_staff(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_auditoria_staff() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_auditoria_usuario_sistema(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_auditoria_usuario_sistema() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_proteger_delete_residente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_proteger_delete_residente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION
        'No se permite eliminar fisicamente un residente (id=%). '
        'Use la baja logica: UPDATE residente SET activo = FALSE.',
        OLD.id_residente;
    RETURN NULL;
END;
$$;


--
-- Name: trg_proteger_log_medicamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_proteger_log_medicamento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'El log de medicamentos es inmutable. No se permite DELETE.';
    RETURN NULL;
END;
$$;


--
-- Name: trg_validar_incidente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_validar_incidente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_validar_sesion_terapia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_validar_sesion_terapia() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: acceso_rfid; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.acceso_rfid (
    id_acceso bigint NOT NULL,
    id_lector integer NOT NULL,
    id_staff integer NOT NULL,
    accedido_en timestamp without time zone DEFAULT now() NOT NULL,
    acceso_concedido boolean DEFAULT true NOT NULL
);


--
-- Name: acceso_rfid_id_acceso_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.acceso_rfid_id_acceso_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acceso_rfid_id_acceso_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.acceso_rfid_id_acceso_seq OWNED BY public.acceso_rfid.id_acceso;


--
-- Name: actividad; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actividad (
    id_actividad integer NOT NULL,
    nombre character varying(100) NOT NULL,
    tipo character varying(20) DEFAULT 'grupal'::character varying NOT NULL,
    descripcion text,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp without time zone DEFAULT now() NOT NULL,
    id_staff_crea integer,
    CONSTRAINT actividad_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['grupal'::character varying, 'individual'::character varying, 'terapia'::character varying, 'recreativa'::character varying])::text[])))
);


--
-- Name: actividad_id_actividad_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actividad_id_actividad_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actividad_id_actividad_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actividad_id_actividad_seq OWNED BY public.actividad.id_actividad;


--
-- Name: ala; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ala (
    id_ala integer NOT NULL,
    nombre character varying(80) NOT NULL,
    piso integer DEFAULT 1 NOT NULL,
    descripcion text,
    activa boolean DEFAULT true NOT NULL,
    CONSTRAINT ala_piso_check CHECK ((piso > 0))
);


--
-- Name: ala_id_ala_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ala_id_ala_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ala_id_ala_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ala_id_ala_seq OWNED BY public.ala.id_ala;


--
-- Name: alerta_gps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerta_gps (
    id_alerta bigint NOT NULL,
    device_id character varying(100) NOT NULL,
    id_zona integer,
    tipo character varying(50) NOT NULL,
    latitud numeric(10,7),
    longitud numeric(11,7),
    mensaje text,
    atendida boolean DEFAULT false,
    ts_alerta timestamp with time zone DEFAULT now()
);


--
-- Name: alerta_gps_id_alerta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.alerta_gps_id_alerta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: alerta_gps_id_alerta_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.alerta_gps_id_alerta_seq OWNED BY public.alerta_gps.id_alerta;


--
-- Name: asignacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asignacion (
    id_asignacion integer NOT NULL,
    id_residente integer NOT NULL,
    id_staff integer NOT NULL,
    tipo_rol character varying(20) NOT NULL,
    fecha_inicio date DEFAULT CURRENT_DATE NOT NULL,
    fecha_fin date,
    es_principal boolean DEFAULT false NOT NULL,
    CONSTRAINT asignacion_tipo_rol_check CHECK (((tipo_rol)::text = ANY ((ARRAY['Cuidador'::character varying, 'Terapeuta'::character varying, 'Medico'::character varying])::text[]))),
    CONSTRAINT ck_asignacion_fechas CHECK (((fecha_fin IS NULL) OR (fecha_fin > fecha_inicio)))
);


--
-- Name: asignacion_id_asignacion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asignacion_id_asignacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asignacion_id_asignacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asignacion_id_asignacion_seq OWNED BY public.asignacion.id_asignacion;


--
-- Name: asistencia_nfc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistencia_nfc (
    id_asistencia bigint NOT NULL,
    id_residente integer NOT NULL,
    id_actividad integer NOT NULL,
    id_staff integer,
    ts_registro timestamp without time zone DEFAULT now() NOT NULL,
    notas text,
    metodo character varying(10) DEFAULT 'nfc'::character varying NOT NULL,
    CONSTRAINT asistencia_nfc_metodo_check CHECK (((metodo)::text = ANY ((ARRAY['nfc'::character varying, 'manual'::character varying])::text[])))
);


--
-- Name: asistencia_nfc_id_asistencia_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asistencia_nfc_id_asistencia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asistencia_nfc_id_asistencia_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asistencia_nfc_id_asistencia_seq OWNED BY public.asistencia_nfc.id_asistencia;


--
-- Name: beacon; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.beacon (
    id_beacon integer NOT NULL,
    id_ala integer NOT NULL,
    nombre character varying(80) NOT NULL
);


--
-- Name: beacon_id_beacon_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.beacon_id_beacon_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: beacon_id_beacon_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.beacon_id_beacon_seq OWNED BY public.beacon.id_beacon;


--
-- Name: checkin_estado_animo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checkin_estado_animo (
    id_checkin integer NOT NULL,
    id_residente integer NOT NULL,
    id_cuidador integer NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    puntaje integer NOT NULL,
    notas text,
    CONSTRAINT checkin_estado_animo_puntaje_check CHECK (((puntaje >= 1) AND (puntaje <= 5)))
);


--
-- Name: checkin_estado_animo_id_checkin_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.checkin_estado_animo_id_checkin_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: checkin_estado_animo_id_checkin_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.checkin_estado_animo_id_checkin_seq OWNED BY public.checkin_estado_animo.id_checkin;


--
-- Name: deteccion_beacon; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deteccion_beacon (
    id_deteccion bigint NOT NULL,
    id_beacon integer NOT NULL,
    id_staff integer NOT NULL,
    detectado_en timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: deteccion_beacon_id_deteccion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deteccion_beacon_id_deteccion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deteccion_beacon_id_deteccion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deteccion_beacon_id_deteccion_seq OWNED BY public.deteccion_beacon.id_deteccion;


--
-- Name: dispositivo_gps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dispositivo_gps (
    id_dispositivo integer NOT NULL,
    device_id character varying(100) NOT NULL,
    id_residente integer,
    nombre character varying(100),
    activo boolean DEFAULT true,
    fecha_alta timestamp with time zone DEFAULT now()
);


--
-- Name: dispositivo_gps_id_dispositivo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dispositivo_gps_id_dispositivo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dispositivo_gps_id_dispositivo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dispositivo_gps_id_dispositivo_seq OWNED BY public.dispositivo_gps.id_dispositivo;


--
-- Name: familiar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.familiar (
    id_familiar integer NOT NULL,
    nombre character varying(100) NOT NULL,
    apellidos character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    telefono character varying(15),
    activo boolean DEFAULT true NOT NULL,
    fecha_registro date DEFAULT CURRENT_DATE NOT NULL
);


--
-- Name: familiar_id_familiar_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.familiar_id_familiar_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: familiar_id_familiar_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.familiar_id_familiar_seq OWNED BY public.familiar.id_familiar;


--
-- Name: familiar_residente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.familiar_residente (
    id_vinculo integer NOT NULL,
    id_familiar integer NOT NULL,
    id_residente integer NOT NULL,
    parentesco character varying(50) DEFAULT 'Familiar'::character varying NOT NULL,
    es_contacto_principal boolean DEFAULT false NOT NULL,
    fecha_inicio date DEFAULT CURRENT_DATE NOT NULL,
    fecha_fin date,
    CONSTRAINT ck_vinculo_fechas CHECK (((fecha_fin IS NULL) OR (fecha_fin > fecha_inicio)))
);


--
-- Name: familiar_residente_id_vinculo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.familiar_residente_id_vinculo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: familiar_residente_id_vinculo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.familiar_residente_id_vinculo_seq OWNED BY public.familiar_residente.id_vinculo;


--
-- Name: gps_ping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gps_ping (
    id_ping bigint NOT NULL,
    id_residente integer NOT NULL,
    latitud numeric(10,7) NOT NULL,
    longitud numeric(10,7) NOT NULL,
    registrado_en timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT gps_ping_latitud_check CHECK (((latitud >= ('-90'::integer)::numeric) AND (latitud <= (90)::numeric))),
    CONSTRAINT gps_ping_longitud_check CHECK (((longitud >= ('-180'::integer)::numeric) AND (longitud <= (180)::numeric)))
);


--
-- Name: gps_ping_id_ping_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gps_ping_id_ping_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gps_ping_id_ping_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gps_ping_id_ping_seq OWNED BY public.gps_ping.id_ping;


--
-- Name: horario_medicamento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.horario_medicamento (
    id_horario integer NOT NULL,
    id_residente integer NOT NULL,
    id_medicamento integer NOT NULL,
    hora_programada time without time zone NOT NULL,
    dosis character varying(30) NOT NULL,
    frecuencia character varying(20) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT horario_medicamento_frecuencia_check CHECK (((frecuencia)::text = ANY ((ARRAY['Diaria'::character varying, 'Semanal'::character varying, 'Mensual'::character varying, 'Condicional'::character varying])::text[])))
);


--
-- Name: horario_medicamento_id_horario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.horario_medicamento_id_horario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: horario_medicamento_id_horario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.horario_medicamento_id_horario_seq OWNED BY public.horario_medicamento.id_horario;


--
-- Name: lector_rfid; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lector_rfid (
    id_lector integer NOT NULL,
    ubicacion character varying(100) NOT NULL,
    es_restringido boolean DEFAULT true NOT NULL,
    id_ala integer,
    id_sala integer
);


--
-- Name: lector_rfid_id_lector_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lector_rfid_id_lector_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lector_rfid_id_lector_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lector_rfid_id_lector_seq OWNED BY public.lector_rfid.id_lector;


--
-- Name: limite_jardin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.limite_jardin (
    id_limite integer NOT NULL,
    descripcion character varying(100),
    lat_min numeric(10,7) NOT NULL,
    lat_max numeric(10,7) NOT NULL,
    lon_min numeric(10,7) NOT NULL,
    lon_max numeric(10,7) NOT NULL,
    CONSTRAINT ck_lat CHECK ((lat_min < lat_max)),
    CONSTRAINT ck_lon CHECK ((lon_min < lon_max))
);


--
-- Name: limite_jardin_id_limite_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.limite_jardin_id_limite_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: limite_jardin_id_limite_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.limite_jardin_id_limite_seq OWNED BY public.limite_jardin.id_limite;


--
-- Name: log_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.log_auditoria (
    id_log bigint NOT NULL,
    id_usuario integer,
    tabla_afectada character varying(80) NOT NULL,
    operacion character varying(10) NOT NULL,
    id_registro integer,
    ip_origen character varying(45),
    timestamp_operacion timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT log_auditoria_operacion_check CHECK (((operacion)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying])::text[])))
);


--
-- Name: log_auditoria_id_log_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.log_auditoria_id_log_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_auditoria_id_log_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.log_auditoria_id_log_seq OWNED BY public.log_auditoria.id_log;


--
-- Name: log_medicamento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.log_medicamento (
    id_log integer NOT NULL,
    id_horario integer NOT NULL,
    id_cuidador integer NOT NULL,
    fecha_administracion timestamp without time zone DEFAULT now() NOT NULL,
    incidente text
);


--
-- Name: log_medicamento_id_log_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.log_medicamento_id_log_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_medicamento_id_log_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.log_medicamento_id_log_seq OWNED BY public.log_medicamento.id_log;


--
-- Name: medicamento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medicamento (
    id_medicamento integer NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion text,
    unidad character varying(20) DEFAULT 'mg'::character varying NOT NULL
);


--
-- Name: medicamento_id_medicamento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.medicamento_id_medicamento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: medicamento_id_medicamento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.medicamento_id_medicamento_seq OWNED BY public.medicamento.id_medicamento;


--
-- Name: nfc_evento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nfc_evento (
    id_evento bigint NOT NULL,
    id_tag integer NOT NULL,
    id_staff integer NOT NULL,
    escaneado_en timestamp without time zone DEFAULT now() NOT NULL,
    id_log_med bigint
);


--
-- Name: nfc_evento_id_evento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nfc_evento_id_evento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nfc_evento_id_evento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nfc_evento_id_evento_seq OWNED BY public.nfc_evento.id_evento;


--
-- Name: nfc_tag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nfc_tag (
    id_tag integer NOT NULL,
    codigo_tag character varying(50) NOT NULL,
    id_residente integer NOT NULL,
    descripcion character varying(100)
);


--
-- Name: nfc_tag_id_tag_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nfc_tag_id_tag_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nfc_tag_id_tag_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nfc_tag_id_tag_seq OWNED BY public.nfc_tag.id_tag;


--
-- Name: pago; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pago (
    id_pago integer NOT NULL,
    id_familiar integer NOT NULL,
    id_residente integer NOT NULL,
    id_plan integer NOT NULL,
    monto numeric(10,2) NOT NULL,
    fecha_pago timestamp without time zone DEFAULT now() NOT NULL,
    metodo_pago character varying(25) NOT NULL,
    referencia character varying(30) NOT NULL,
    estado character varying(15) DEFAULT 'Completado'::character varying NOT NULL,
    periodo_mes integer NOT NULL,
    periodo_anio integer NOT NULL,
    concepto character varying(150),
    CONSTRAINT pago_estado_check CHECK (((estado)::text = ANY ((ARRAY['Completado'::character varying, 'Pendiente'::character varying, 'Rechazado'::character varying])::text[]))),
    CONSTRAINT pago_metodo_pago_check CHECK (((metodo_pago)::text = ANY ((ARRAY['Tarjeta de crédito'::character varying, 'Transferencia SPEI'::character varying, 'OXXO Pay'::character varying])::text[]))),
    CONSTRAINT pago_monto_check CHECK ((monto > (0)::numeric)),
    CONSTRAINT pago_periodo_anio_check CHECK ((periodo_anio >= 2020)),
    CONSTRAINT pago_periodo_mes_check CHECK (((periodo_mes >= 1) AND (periodo_mes <= 12)))
);


--
-- Name: pago_id_pago_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pago_id_pago_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pago_id_pago_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pago_id_pago_seq OWNED BY public.pago.id_pago;


--
-- Name: plan_residente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_residente (
    id_plan integer NOT NULL,
    id_residente integer NOT NULL,
    tipo_plan character varying(20) NOT NULL,
    monto_mensual numeric(10,2) NOT NULL,
    fecha_inicio date DEFAULT CURRENT_DATE NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT plan_residente_tipo_plan_check CHECK (((tipo_plan)::text = ANY ((ARRAY['Esencial'::character varying, 'Bienestar'::character varying, 'Premium'::character varying])::text[])))
);


--
-- Name: plan_residente_id_plan_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.plan_residente_id_plan_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plan_residente_id_plan_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.plan_residente_id_plan_seq OWNED BY public.plan_residente.id_plan;


--
-- Name: posicion_gps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posicion_gps (
    id_posicion bigint NOT NULL,
    device_id character varying(100) NOT NULL,
    latitud numeric(10,7) NOT NULL,
    longitud numeric(11,7) NOT NULL,
    altitud numeric(8,2),
    velocidad_kmh numeric(6,2),
    rumbo numeric(5,1),
    precision_m numeric(8,2),
    bateria smallint,
    ts_dispositivo timestamp with time zone,
    ts_servidor timestamp with time zone DEFAULT now()
);


--
-- Name: posicion_gps_id_posicion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posicion_gps_id_posicion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posicion_gps_id_posicion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posicion_gps_id_posicion_seq OWNED BY public.posicion_gps.id_posicion;


--
-- Name: reporte_incidente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reporte_incidente (
    id_incidente integer NOT NULL,
    id_residente integer NOT NULL,
    id_staff integer NOT NULL,
    fecha timestamp without time zone DEFAULT now() NOT NULL,
    tipo character varying(30) NOT NULL,
    descripcion text NOT NULL,
    severidad character varying(10) NOT NULL,
    CONSTRAINT reporte_incidente_severidad_check CHECK (((severidad)::text = ANY ((ARRAY['Baja'::character varying, 'Media'::character varying, 'Alta'::character varying])::text[]))),
    CONSTRAINT reporte_incidente_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['Caida'::character varying, 'Agitacion'::character varying, 'Deambulacion'::character varying, 'Rechazo_Medicamento'::character varying, 'Otro'::character varying])::text[])))
);


--
-- Name: reporte_incidente_id_incidente_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reporte_incidente_id_incidente_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reporte_incidente_id_incidente_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reporte_incidente_id_incidente_seq OWNED BY public.reporte_incidente.id_incidente;


--
-- Name: residente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.residente (
    id_residente integer NOT NULL,
    nombre character varying(100) NOT NULL,
    apellidos character varying(100) NOT NULL,
    fecha_nacimiento date NOT NULL,
    sexo character(1) NOT NULL,
    habitacion character varying(10),
    diagnostico_principal text,
    nivel_movilidad character varying(20) DEFAULT 'Autonomo'::character varying NOT NULL,
    contacto_emergencia character varying(100),
    tel_emergencia character varying(15),
    fecha_ingreso date DEFAULT CURRENT_DATE NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_residente_edad CHECK ((fecha_nacimiento <= (CURRENT_DATE - '65 years'::interval))),
    CONSTRAINT residente_nivel_movilidad_check CHECK (((nivel_movilidad)::text = ANY ((ARRAY['Autonomo'::character varying, 'Asistido'::character varying, 'Encamado'::character varying])::text[]))),
    CONSTRAINT residente_sexo_check CHECK ((sexo = ANY (ARRAY['M'::bpchar, 'F'::bpchar])))
);


--
-- Name: residente_id_residente_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.residente_id_residente_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: residente_id_residente_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.residente_id_residente_seq OWNED BY public.residente.id_residente;


--
-- Name: rol; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rol (
    id_rol integer NOT NULL,
    nombre_rol character varying(50) NOT NULL,
    nivel_acceso integer NOT NULL,
    CONSTRAINT rol_nivel_acceso_check CHECK (((nivel_acceso >= 1) AND (nivel_acceso <= 3)))
);


--
-- Name: rol_id_rol_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rol_id_rol_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rol_id_rol_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rol_id_rol_seq OWNED BY public.rol.id_rol;


--
-- Name: sala; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sala (
    id_sala integer NOT NULL,
    nombre character varying(80) NOT NULL,
    id_ala integer NOT NULL,
    capacidad integer DEFAULT 1 NOT NULL,
    CONSTRAINT sala_capacidad_check CHECK ((capacidad > 0))
);


--
-- Name: sala_id_sala_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sala_id_sala_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sala_id_sala_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sala_id_sala_seq OWNED BY public.sala.id_sala;


--
-- Name: sesion_terapia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sesion_terapia (
    id_sesion integer NOT NULL,
    id_residente integer NOT NULL,
    id_terapeuta integer NOT NULL,
    id_sala integer NOT NULL,
    fecha_sesion timestamp without time zone NOT NULL,
    tipo_sesion character varying(20) NOT NULL,
    duracion_min integer NOT NULL,
    asistio boolean DEFAULT true NOT NULL,
    notas text,
    CONSTRAINT sesion_terapia_duracion_min_check CHECK (((duracion_min > 0) AND (duracion_min <= 480))),
    CONSTRAINT sesion_terapia_tipo_sesion_check CHECK (((tipo_sesion)::text = ANY ((ARRAY['Individual'::character varying, 'Grupal'::character varying, 'Virtual'::character varying])::text[])))
);


--
-- Name: sesion_terapia_id_sesion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sesion_terapia_id_sesion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sesion_terapia_id_sesion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sesion_terapia_id_sesion_seq OWNED BY public.sesion_terapia.id_sesion;


--
-- Name: staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff (
    id_staff integer NOT NULL,
    nombre character varying(100) NOT NULL,
    apellidos character varying(100) NOT NULL,
    especialidad character varying(80) NOT NULL,
    email character varying(100) NOT NULL,
    id_rol integer NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    fecha_alta date DEFAULT CURRENT_DATE NOT NULL
);


--
-- Name: staff_id_staff_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.staff_id_staff_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: staff_id_staff_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.staff_id_staff_seq OWNED BY public.staff.id_staff;


--
-- Name: turno; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turno (
    id_turno integer NOT NULL,
    id_staff integer NOT NULL,
    id_ala integer NOT NULL,
    fecha date NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL,
    CONSTRAINT ck_turno_horas CHECK ((hora_fin > hora_inicio))
);


--
-- Name: turno_id_turno_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.turno_id_turno_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: turno_id_turno_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.turno_id_turno_seq OWNED BY public.turno.id_turno;


--
-- Name: usuario_familiar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_familiar (
    id_usuario integer NOT NULL,
    username character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    id_familiar integer NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    ultimo_login timestamp without time zone
);


--
-- Name: usuario_familiar_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuario_familiar_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuario_familiar_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuario_familiar_id_usuario_seq OWNED BY public.usuario_familiar.id_usuario;


--
-- Name: usuario_sistema; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_sistema (
    id_usuario integer NOT NULL,
    username character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    id_staff integer NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    ultimo_login timestamp without time zone
);


--
-- Name: usuario_sistema_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuario_sistema_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuario_sistema_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuario_sistema_id_usuario_seq OWNED BY public.usuario_sistema.id_usuario;


--
-- Name: v_accesos_rfid_hoy; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_accesos_rfid_hoy AS
 SELECT ar.id_acceso,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS staff,
    s.especialidad,
    lr.ubicacion,
    lr.ubicacion AS lector,
    a.nombre AS ala,
    lr.es_restringido,
    ar.acceso_concedido,
    ar.acceso_concedido AS autorizado,
    to_char(ar.accedido_en, 'HH12:MI AM'::text) AS hora
   FROM (((public.acceso_rfid ar
     JOIN public.staff s ON ((ar.id_staff = s.id_staff)))
     JOIN public.lector_rfid lr ON ((ar.id_lector = lr.id_lector)))
     LEFT JOIN public.ala a ON ((lr.id_ala = a.id_ala)))
  WHERE ((ar.accedido_en)::date = CURRENT_DATE)
  ORDER BY ar.accedido_en DESC;


--
-- Name: v_adherencia_medicamentos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_adherencia_medicamentos AS
 SELECT r.id_residente,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    count(hm.id_horario) AS dosis_programadas,
    count(lm.id_log) AS dosis_administradas,
    (count(hm.id_horario) - count(lm.id_log)) AS dosis_pendientes,
    round((((count(lm.id_log))::numeric / (NULLIF(count(hm.id_horario), 0))::numeric) * (100)::numeric), 1) AS pct_adherencia
   FROM ((public.residente r
     JOIN public.horario_medicamento hm ON (((hm.id_residente = r.id_residente) AND (hm.activo = true))))
     LEFT JOIN public.log_medicamento lm ON (((lm.id_horario = hm.id_horario) AND ((lm.fecha_administracion)::date = CURRENT_DATE))))
  WHERE (r.activo = true)
  GROUP BY r.id_residente, r.nombre, r.apellidos, r.habitacion
  ORDER BY (round((((count(lm.id_log))::numeric / (NULLIF(count(hm.id_horario), 0))::numeric) * (100)::numeric), 1));


--
-- Name: v_estado_gps_residentes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_estado_gps_residentes AS
 SELECT r.id_residente,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    g.latitud,
    g.longitud,
    g.registrado_en,
    (((g.latitud >= lj.lat_min) AND (g.latitud <= lj.lat_max)) AND ((g.longitud >= lj.lon_min) AND (g.longitud <= lj.lon_max))) AS dentro_limite,
    (EXTRACT(epoch FROM (now() - (g.registrado_en)::timestamp with time zone)) / (60)::numeric) AS minutos_desde_ping
   FROM ((public.residente r
     JOIN LATERAL ( SELECT gps_ping.latitud,
            gps_ping.longitud,
            gps_ping.registrado_en
           FROM public.gps_ping
          WHERE (gps_ping.id_residente = r.id_residente)
          ORDER BY gps_ping.registrado_en DESC
         LIMIT 1) g ON (true))
     CROSS JOIN public.limite_jardin lj)
  WHERE (r.activo = true)
  ORDER BY (((g.latitud >= lj.lat_min) AND (g.latitud <= lj.lat_max)) AND ((g.longitud >= lj.lon_min) AND (g.longitud <= lj.lon_max))), (EXTRACT(epoch FROM (now() - (g.registrado_en)::timestamp with time zone)) / (60)::numeric);


--
-- Name: v_familiar_animo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_familiar_animo AS
 SELECT id_residente,
    fecha_registro,
    puntaje,
    to_char(fecha_registro, 'DD Mon'::text) AS etiqueta
   FROM public.checkin_estado_animo cea
  WHERE (fecha_registro >= (now() - '30 days'::interval))
  ORDER BY fecha_registro;


--
-- Name: v_familiar_incidentes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_familiar_incidentes AS
 SELECT id_incidente,
    id_residente,
    tipo,
    severidad,
    to_char(fecha, 'DD Mon YYYY HH12:MI AM'::text) AS fecha,
        CASE
            WHEN ((tipo)::text = ANY ((ARRAY['Caida'::character varying, 'Deambulacion'::character varying])::text[])) THEN descripcion
            ELSE 'Informacion clinica reservada.'::text
        END AS descripcion_visible
   FROM public.reporte_incidente ri
  WHERE (fecha >= (now() - '30 days'::interval))
  ORDER BY ri.fecha DESC;


--
-- Name: v_familiar_medicamentos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_familiar_medicamentos AS
 SELECT hm.id_horario,
    hm.id_residente,
    m.nombre AS medicamento,
    hm.dosis,
    hm.hora_programada,
    hm.frecuencia,
    (EXISTS ( SELECT 1
           FROM public.log_medicamento lm
          WHERE ((lm.id_horario = hm.id_horario) AND ((lm.fecha_administracion)::date = CURRENT_DATE)))) AS administrado_hoy
   FROM (public.horario_medicamento hm
     JOIN public.medicamento m ON ((hm.id_medicamento = m.id_medicamento)))
  WHERE (hm.activo = true)
  ORDER BY hm.hora_programada;


--
-- Name: v_familiar_residente_info; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_familiar_residente_info AS
 SELECT r.id_residente,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    r.diagnostico_principal,
    r.nivel_movilidad,
    (EXTRACT(year FROM age((r.fecha_nacimiento)::timestamp with time zone)))::integer AS edad,
    r.fecha_ingreso,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS cuidador_principal,
    c.puntaje AS ultimo_puntaje_animo,
    to_char(c.fecha_registro, 'DD Mon YYYY HH12:MI AM'::text) AS fecha_ultimo_checkin,
    fr.id_familiar,
    fr.parentesco,
    fr.es_contacto_principal
   FROM (((((public.residente r
     JOIN public.familiar_residente fr ON (((fr.id_residente = r.id_residente) AND (fr.fecha_fin IS NULL))))
     JOIN public.familiar f ON (((f.id_familiar = fr.id_familiar) AND (f.activo = true))))
     LEFT JOIN public.asignacion a ON (((a.id_residente = r.id_residente) AND ((a.tipo_rol)::text = 'Cuidador'::text) AND (a.es_principal = true) AND (a.fecha_fin IS NULL))))
     LEFT JOIN public.staff s ON ((s.id_staff = a.id_staff)))
     LEFT JOIN LATERAL ( SELECT checkin_estado_animo.puntaje,
            checkin_estado_animo.fecha_registro
           FROM public.checkin_estado_animo
          WHERE (checkin_estado_animo.id_residente = r.id_residente)
          ORDER BY checkin_estado_animo.fecha_registro DESC
         LIMIT 1) c ON (true))
  WHERE (r.activo = true);


--
-- Name: v_familiar_sesiones; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_familiar_sesiones AS
 SELECT st.id_sesion,
    st.id_residente,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS terapeuta,
    sa.nombre AS sala,
    st.tipo_sesion,
    st.duracion_min,
    to_char(st.fecha_sesion, 'DD Mon YYYY HH12:MI AM'::text) AS fecha_hora,
    st.asistio
   FROM ((public.sesion_terapia st
     JOIN public.staff s ON ((st.id_terapeuta = s.id_staff)))
     JOIN public.sala sa ON ((st.id_sala = sa.id_sala)))
  ORDER BY st.fecha_sesion DESC;


--
-- Name: v_incidentes_recientes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_incidentes_recientes AS
 SELECT ri.id_incidente,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS reportado_por,
    ri.tipo,
    ri.severidad,
    ri.descripcion,
    to_char(ri.fecha, 'DD Mon HH12:MI AM'::text) AS fecha
   FROM ((public.reporte_incidente ri
     JOIN public.residente r ON ((ri.id_residente = r.id_residente)))
     JOIN public.staff s ON ((ri.id_staff = s.id_staff)))
  WHERE (ri.fecha >= (now() - '7 days'::interval))
  ORDER BY
        CASE ri.severidad
            WHEN 'Alta'::text THEN 1
            WHEN 'Media'::text THEN 2
            ELSE 3
        END, ri.fecha DESC;


--
-- Name: v_medicamentos_pendientes_hoy; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_medicamentos_pendientes_hoy AS
 SELECT hm.id_horario,
    r.id_residente,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    m.nombre AS medicamento,
    hm.dosis,
    hm.hora_programada,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS cuidador_asignado
   FROM ((((public.horario_medicamento hm
     JOIN public.residente r ON ((hm.id_residente = r.id_residente)))
     JOIN public.medicamento m ON ((hm.id_medicamento = m.id_medicamento)))
     LEFT JOIN public.asignacion a ON (((a.id_residente = r.id_residente) AND ((a.tipo_rol)::text = 'Cuidador'::text) AND (a.es_principal = true) AND (a.fecha_fin IS NULL))))
     LEFT JOIN public.staff s ON ((s.id_staff = a.id_staff)))
  WHERE ((hm.activo = true) AND (r.activo = true) AND (NOT (EXISTS ( SELECT 1
           FROM public.log_medicamento lm
          WHERE ((lm.id_horario = hm.id_horario) AND ((lm.fecha_administracion)::date = CURRENT_DATE))))))
  ORDER BY hm.hora_programada;


--
-- Name: v_residentes_resumen; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_residentes_resumen AS
 SELECT r.id_residente,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    r.diagnostico_principal,
    r.nivel_movilidad,
    (EXTRACT(year FROM age((r.fecha_nacimiento)::timestamp with time zone)))::integer AS edad,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS cuidador_principal,
    c.puntaje AS ultimo_puntaje_animo,
    to_char(c.fecha_registro, 'DD Mon HH12:MI AM'::text) AS fecha_ultimo_checkin,
    r.fecha_ingreso
   FROM (((public.residente r
     LEFT JOIN public.asignacion a ON (((a.id_residente = r.id_residente) AND ((a.tipo_rol)::text = 'Cuidador'::text) AND (a.es_principal = true) AND (a.fecha_fin IS NULL))))
     LEFT JOIN public.staff s ON ((s.id_staff = a.id_staff)))
     LEFT JOIN LATERAL ( SELECT checkin_estado_animo.puntaje,
            checkin_estado_animo.fecha_registro
           FROM public.checkin_estado_animo
          WHERE (checkin_estado_animo.id_residente = r.id_residente)
          ORDER BY checkin_estado_animo.fecha_registro DESC
         LIMIT 1) c ON (true))
  WHERE (r.activo = true)
  ORDER BY r.apellidos;


--
-- Name: v_resumen_incidentes_mes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_resumen_incidentes_mes AS
 SELECT to_char(fecha, 'YYYY-MM'::text) AS mes,
    tipo,
    severidad,
    count(*) AS total,
    count(DISTINCT id_residente) AS residentes_afectados,
    round((((count(*))::numeric * 100.0) / sum(count(*)) OVER (PARTITION BY (to_char(fecha, 'YYYY-MM'::text)))), 1) AS pct_del_mes
   FROM public.reporte_incidente ri
  WHERE (fecha >= (now() - '6 mons'::interval))
  GROUP BY (to_char(fecha, 'YYYY-MM'::text)), tipo, severidad
  ORDER BY (to_char(fecha, 'YYYY-MM'::text)) DESC, (count(*)) DESC;


--
-- Name: v_sesiones_hoy; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sesiones_hoy AS
 SELECT st.id_sesion,
    (((r.nombre)::text || ' '::text) || (r.apellidos)::text) AS residente,
    r.habitacion,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS terapeuta,
    sa.nombre AS sala,
    st.tipo_sesion,
    st.duracion_min,
    to_char(st.fecha_sesion, 'HH12:MI AM'::text) AS hora,
    st.asistio
   FROM (((public.sesion_terapia st
     JOIN public.residente r ON ((st.id_residente = r.id_residente)))
     JOIN public.staff s ON ((st.id_terapeuta = s.id_staff)))
     JOIN public.sala sa ON ((st.id_sala = sa.id_sala)))
  WHERE ((st.fecha_sesion)::date = CURRENT_DATE)
  ORDER BY st.fecha_sesion;


--
-- Name: v_staff_en_turno_hoy; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_staff_en_turno_hoy AS
 SELECT s.id_staff,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS staff,
    s.especialidad,
    r.nombre_rol AS rol,
    a.nombre AS ala,
    t.hora_inicio,
    t.hora_fin
   FROM (((public.turno t
     JOIN public.staff s ON ((t.id_staff = s.id_staff)))
     JOIN public.ala a ON ((t.id_ala = a.id_ala)))
     JOIN public.rol r ON ((s.id_rol = r.id_rol)))
  WHERE ((t.fecha = CURRENT_DATE) AND (s.activo = true))
  ORDER BY a.nombre, t.hora_inicio;


--
-- Name: v_ubicacion_actual_staff; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ubicacion_actual_staff AS
 SELECT s.id_staff,
    (((s.nombre)::text || ' '::text) || (s.apellidos)::text) AS staff,
    s.especialidad,
    r.nombre_rol AS rol,
    a.nombre AS ala_detectada,
    to_char(db.detectado_en, 'HH12:MI AM'::text) AS ultima_deteccion,
    (EXTRACT(epoch FROM (now() - (db.detectado_en)::timestamp with time zone)) / (60)::numeric) AS minutos_desde_deteccion
   FROM ((((public.staff s
     JOIN public.rol r ON ((s.id_rol = r.id_rol)))
     JOIN public.turno t ON (((t.id_staff = s.id_staff) AND (t.fecha = CURRENT_DATE))))
     LEFT JOIN LATERAL ( SELECT db2.detectado_en,
            b.id_ala
           FROM (public.deteccion_beacon db2
             JOIN public.beacon b ON ((db2.id_beacon = b.id_beacon)))
          WHERE (db2.id_staff = s.id_staff)
          ORDER BY db2.detectado_en DESC
         LIMIT 1) db ON (true))
     LEFT JOIN public.ala a ON ((db.id_ala = a.id_ala)))
  WHERE (s.activo = true)
  ORDER BY a.nombre, s.apellidos;


--
-- Name: zona_gps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.zona_gps (
    id_zona integer NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion text,
    latitud numeric(10,7) NOT NULL,
    longitud numeric(11,7) NOT NULL,
    radio_m integer DEFAULT 50 NOT NULL,
    tipo character varying(20) DEFAULT 'peligrosa'::character varying NOT NULL,
    color character varying(7) DEFAULT '#EF4444'::character varying,
    activo boolean DEFAULT true,
    creado_en timestamp with time zone DEFAULT now(),
    CONSTRAINT zona_gps_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['peligrosa'::character varying, 'segura'::character varying])::text[])))
);


--
-- Name: zona_gps_id_zona_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.zona_gps_id_zona_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: zona_gps_id_zona_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.zona_gps_id_zona_seq OWNED BY public.zona_gps.id_zona;


--
-- Name: acceso_rfid id_acceso; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acceso_rfid ALTER COLUMN id_acceso SET DEFAULT nextval('public.acceso_rfid_id_acceso_seq'::regclass);


--
-- Name: actividad id_actividad; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad ALTER COLUMN id_actividad SET DEFAULT nextval('public.actividad_id_actividad_seq'::regclass);


--
-- Name: ala id_ala; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ala ALTER COLUMN id_ala SET DEFAULT nextval('public.ala_id_ala_seq'::regclass);


--
-- Name: alerta_gps id_alerta; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerta_gps ALTER COLUMN id_alerta SET DEFAULT nextval('public.alerta_gps_id_alerta_seq'::regclass);


--
-- Name: asignacion id_asignacion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asignacion ALTER COLUMN id_asignacion SET DEFAULT nextval('public.asignacion_id_asignacion_seq'::regclass);


--
-- Name: asistencia_nfc id_asistencia; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencia_nfc ALTER COLUMN id_asistencia SET DEFAULT nextval('public.asistencia_nfc_id_asistencia_seq'::regclass);


--
-- Name: beacon id_beacon; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beacon ALTER COLUMN id_beacon SET DEFAULT nextval('public.beacon_id_beacon_seq'::regclass);


--
-- Name: checkin_estado_animo id_checkin; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_estado_animo ALTER COLUMN id_checkin SET DEFAULT nextval('public.checkin_estado_animo_id_checkin_seq'::regclass);


--
-- Name: deteccion_beacon id_deteccion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deteccion_beacon ALTER COLUMN id_deteccion SET DEFAULT nextval('public.deteccion_beacon_id_deteccion_seq'::regclass);


--
-- Name: dispositivo_gps id_dispositivo; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispositivo_gps ALTER COLUMN id_dispositivo SET DEFAULT nextval('public.dispositivo_gps_id_dispositivo_seq'::regclass);


--
-- Name: familiar id_familiar; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar ALTER COLUMN id_familiar SET DEFAULT nextval('public.familiar_id_familiar_seq'::regclass);


--
-- Name: familiar_residente id_vinculo; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar_residente ALTER COLUMN id_vinculo SET DEFAULT nextval('public.familiar_residente_id_vinculo_seq'::regclass);


--
-- Name: gps_ping id_ping; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gps_ping ALTER COLUMN id_ping SET DEFAULT nextval('public.gps_ping_id_ping_seq'::regclass);


--
-- Name: horario_medicamento id_horario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_medicamento ALTER COLUMN id_horario SET DEFAULT nextval('public.horario_medicamento_id_horario_seq'::regclass);


--
-- Name: lector_rfid id_lector; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lector_rfid ALTER COLUMN id_lector SET DEFAULT nextval('public.lector_rfid_id_lector_seq'::regclass);


--
-- Name: limite_jardin id_limite; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.limite_jardin ALTER COLUMN id_limite SET DEFAULT nextval('public.limite_jardin_id_limite_seq'::regclass);


--
-- Name: log_auditoria id_log; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_auditoria ALTER COLUMN id_log SET DEFAULT nextval('public.log_auditoria_id_log_seq'::regclass);


--
-- Name: log_medicamento id_log; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_medicamento ALTER COLUMN id_log SET DEFAULT nextval('public.log_medicamento_id_log_seq'::regclass);


--
-- Name: medicamento id_medicamento; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medicamento ALTER COLUMN id_medicamento SET DEFAULT nextval('public.medicamento_id_medicamento_seq'::regclass);


--
-- Name: nfc_evento id_evento; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_evento ALTER COLUMN id_evento SET DEFAULT nextval('public.nfc_evento_id_evento_seq'::regclass);


--
-- Name: nfc_tag id_tag; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_tag ALTER COLUMN id_tag SET DEFAULT nextval('public.nfc_tag_id_tag_seq'::regclass);


--
-- Name: pago id_pago; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pago ALTER COLUMN id_pago SET DEFAULT nextval('public.pago_id_pago_seq'::regclass);


--
-- Name: plan_residente id_plan; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_residente ALTER COLUMN id_plan SET DEFAULT nextval('public.plan_residente_id_plan_seq'::regclass);


--
-- Name: posicion_gps id_posicion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posicion_gps ALTER COLUMN id_posicion SET DEFAULT nextval('public.posicion_gps_id_posicion_seq'::regclass);


--
-- Name: reporte_incidente id_incidente; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reporte_incidente ALTER COLUMN id_incidente SET DEFAULT nextval('public.reporte_incidente_id_incidente_seq'::regclass);


--
-- Name: residente id_residente; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.residente ALTER COLUMN id_residente SET DEFAULT nextval('public.residente_id_residente_seq'::regclass);


--
-- Name: rol id_rol; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol ALTER COLUMN id_rol SET DEFAULT nextval('public.rol_id_rol_seq'::regclass);


--
-- Name: sala id_sala; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sala ALTER COLUMN id_sala SET DEFAULT nextval('public.sala_id_sala_seq'::regclass);


--
-- Name: sesion_terapia id_sesion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesion_terapia ALTER COLUMN id_sesion SET DEFAULT nextval('public.sesion_terapia_id_sesion_seq'::regclass);


--
-- Name: staff id_staff; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff ALTER COLUMN id_staff SET DEFAULT nextval('public.staff_id_staff_seq'::regclass);


--
-- Name: turno id_turno; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turno ALTER COLUMN id_turno SET DEFAULT nextval('public.turno_id_turno_seq'::regclass);


--
-- Name: usuario_familiar id_usuario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_familiar ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_familiar_id_usuario_seq'::regclass);


--
-- Name: usuario_sistema id_usuario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_sistema ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_sistema_id_usuario_seq'::regclass);


--
-- Name: zona_gps id_zona; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zona_gps ALTER COLUMN id_zona SET DEFAULT nextval('public.zona_gps_id_zona_seq'::regclass);


--
-- Data for Name: acceso_rfid; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.acceso_rfid (id_acceso, id_lector, id_staff, accedido_en, acceso_concedido) FROM stdin;
1	1	4	2026-04-20 06:19:11.952321	t
2	3	2	2026-04-20 07:19:11.952321	t
3	3	3	2026-04-20 08:19:11.952321	t
4	2	5	2026-04-20 11:19:11.952321	t
5	1	2	2026-05-14 15:09:33.999217	t
6	1	1	2026-05-14 15:10:03.248073	t
7	2	1	2026-05-14 15:10:19.812567	t
8	1	6	2026-05-14 15:27:07.715788	t
9	2	1	2026-05-14 15:27:17.966646	t
10	3	6	2026-05-14 15:27:38.456332	t
11	1	1	2026-05-14 15:39:47.141	t
12	2	4	2026-05-14 15:39:55.035432	t
13	2	6	2026-05-14 15:43:08.707511	t
\.


--
-- Data for Name: actividad; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.actividad (id_actividad, nombre, tipo, descripcion, activo, creado_en, id_staff_crea) FROM stdin;
3	Terapia ocupacional	individual	Actividades manuales individualizadas	t	2026-05-13 13:23:01.043434	\N
4	Recreacion y juegos	recreativa	Juegos de mesa y actividades lÃºdicas	t	2026-05-13 13:23:01.043434	\N
2	Sesion de musicoterapia	terapia	SesiÃ³n grupal de estimulaciÃ³n auditiva	t	2026-05-13 13:23:01.043434	\N
1	Terapia fisica grupal	grupal	Ejercicios de movilidad en salÃ³n principal	t	2026-05-13 13:23:01.043434	\N
\.


--
-- Data for Name: ala; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ala (id_ala, nombre, piso, descripcion, activa) FROM stdin;
1	Ala A - Demencia	1	Residentes con demencia y deterioro cognitivo severo	t
2	Ala B - Ambulatorio	1	Residentes con movilidad autonoma o asistida	t
3	Patio y Jardin	1	Area exterior del asilo	t
\.


--
-- Data for Name: alerta_gps; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.alerta_gps (id_alerta, device_id, id_zona, tipo, latitud, longitud, mensaje, atendida, ts_alerta) FROM stdin;
1	67108604	5	entrada_zona_peligrosa	25.6635853	-100.4216087	Residente detectado en zona peligrosa 'ESTOA' (22 m del centro)	t	2026-05-18 12:07:01.268459-06
2	67108604	5	entrada_zona_peligrosa	25.6635853	-100.4216087	Residente detectado en zona peligrosa 'ESTOA' (22 m del centro)	t	2026-05-18 12:21:00.773652-06
3	67108604	5	entrada_zona_peligrosa	25.6635853	-100.4216087	Residente detectado en zona peligrosa 'ESTOA' (22 m del centro)	t	2026-05-18 12:21:11.61351-06
\.


--
-- Data for Name: asignacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.asignacion (id_asignacion, id_residente, id_staff, tipo_rol, fecha_inicio, fecha_fin, es_principal) FROM stdin;
1	1	4	Cuidador	2026-04-20	\N	t
2	1	5	Cuidador	2026-04-20	\N	f
3	1	2	Terapeuta	2026-04-20	\N	f
4	2	4	Cuidador	2026-04-20	\N	t
5	2	2	Terapeuta	2026-04-20	\N	f
7	3	3	Terapeuta	2026-04-20	\N	f
8	4	6	Cuidador	2026-04-20	\N	t
9	4	3	Terapeuta	2026-04-20	\N	f
10	6	5	Cuidador	2026-04-20	2026-04-23	t
11	7	6	Cuidador	2026-04-23	2026-05-14	t
6	3	6	Cuidador	2026-04-20	2026-05-15	t
12	3	4	Cuidador	2026-05-15	\N	t
\.


--
-- Data for Name: asistencia_nfc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.asistencia_nfc (id_asistencia, id_residente, id_actividad, id_staff, ts_registro, notas, metodo) FROM stdin;
1	1	4	\N	2026-05-14 15:02:13.522817	\N	nfc
2	3	4	\N	2026-05-14 20:18:52.815758	Si	nfc
3	3	3	\N	2026-05-18 11:42:27.382617	asd	nfc
4	3	3	\N	2026-05-18 11:42:33.212357	dsa	nfc
5	3	4	\N	2026-05-18 11:42:39.253904	oh si	nfc
6	3	4	\N	2026-05-18 12:12:13.018282	\N	nfc
7	3	3	\N	2026-05-18 12:12:46.142996	Probando	nfc
8	3	2	\N	2026-05-18 12:20:21.733663	Probando 2.0	nfc
\.


--
-- Data for Name: beacon; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.beacon (id_beacon, id_ala, nombre) FROM stdin;
1	1	Beacon-AlaA-Corredor
2	2	Beacon-AlaB-Corredor
3	2	Beacon-AlaB-SalaGrupal
4	2	Beacon-AlaB-Demo
\.


--
-- Data for Name: checkin_estado_animo; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.checkin_estado_animo (id_checkin, id_residente, id_cuidador, fecha_registro, puntaje, notas) FROM stdin;
1	2	4	2026-04-17 13:19:11.952321	4	Tranquila pero con poco apetito.
2	2	4	2026-04-18 13:19:11.952321	3	Llanto espontaneo durante la tarde.
3	2	4	2026-04-19 13:19:11.952321	2	No quiso salir de la habitacion. [AUTO-INCIDENTE Media]
4	2	4	2026-04-20 13:19:11.952321	1	Crisis de angustia severa. [AUTO-INCIDENTE Alta]
5	1	4	2026-04-20 05:19:11.952321	3	Turno matutino - Maria: confusion moderada al despertar, orientado hacia el mediodia.
6	1	5	2026-04-20 12:19:11.952321	3	Turno nocturno - Pedro: tranquilo, tomo la cena completa, sin incidencias.
7	3	6	2026-04-19 13:19:11.952321	4	Bien. Practico respiracion con Ana.
8	4	6	2026-04-19 13:19:11.952321	3	Algo desorientada por la tarde, requirio acompanamiento.
9	1	4	2026-04-20 13:53:24.820175	4	bien
10	2	4	2026-05-14 13:27:51.513121	4	\N
11	1	4	2026-05-18 11:59:34.139688	3	bla\r\n
\.


--
-- Data for Name: deteccion_beacon; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deteccion_beacon (id_deteccion, id_beacon, id_staff, detectado_en) FROM stdin;
1	1	4	2026-04-20 07:19:11.952321
2	1	6	2026-04-20 08:19:11.952321
3	2	5	2026-04-20 11:19:11.952321
4	2	2	2026-04-20 09:19:11.952321
5	3	3	2026-04-20 10:19:11.952321
6	1	4	2026-04-20 12:19:11.952321
7	1	6	2026-04-20 12:49:11.952321
8	1	4	2026-04-28 16:44:20.922781
9	1	4	2026-04-28 16:44:34.101685
10	1	4	2026-04-28 16:44:47.230365
11	1	4	2026-04-28 16:45:00.311993
12	1	1	2026-05-14 13:53:53.686257
13	1	1	2026-05-14 13:54:06.861983
14	1	1	2026-05-14 13:54:19.972303
15	1	1	2026-05-14 13:54:33.114172
16	1	1	2026-05-14 13:54:46.218474
17	1	1	2026-05-14 13:54:59.355931
18	1	1	2026-05-14 13:55:12.47634
19	1	1	2026-05-14 13:55:25.581356
20	1	1	2026-05-14 13:55:38.691265
21	1	1	2026-05-14 13:55:51.790681
22	1	1	2026-05-14 13:56:04.912346
23	1	1	2026-05-14 13:58:44.179916
24	1	1	2026-05-14 13:58:57.308743
25	1	4	2026-05-14 21:15:47.788847
26	1	4	2026-05-14 21:16:00.873041
27	4	5	2026-05-14 21:16:08.382461
28	1	4	2026-05-14 21:16:13.973343
29	4	5	2026-05-14 21:16:21.481596
30	1	4	2026-05-14 21:16:27.074777
31	4	5	2026-05-14 21:16:34.586239
32	1	4	2026-05-14 21:16:40.164279
33	4	5	2026-05-14 21:16:47.707417
34	1	4	2026-05-14 21:16:53.283552
35	4	5	2026-05-14 21:17:00.855212
36	1	4	2026-05-14 21:17:06.398984
37	4	5	2026-05-14 21:17:13.969896
38	1	4	2026-05-14 21:17:19.534367
39	4	5	2026-05-14 21:17:27.081961
40	1	4	2026-05-14 21:17:32.665731
41	4	5	2026-05-14 21:17:40.177345
42	1	4	2026-05-14 21:17:45.769694
43	1	4	2026-05-18 11:28:28.09024
44	1	4	2026-05-18 11:28:41.31558
45	1	4	2026-05-18 11:28:54.429235
46	1	4	2026-05-18 11:29:07.567496
47	1	4	2026-05-18 11:29:20.657316
48	1	4	2026-05-18 11:29:33.765945
49	1	4	2026-05-18 11:29:46.887589
50	1	4	2026-05-18 11:30:00.003762
51	1	4	2026-05-18 11:30:13.059818
52	1	4	2026-05-18 11:30:26.177572
53	1	4	2026-05-18 11:30:39.264917
54	1	4	2026-05-18 11:30:52.347794
55	1	4	2026-05-18 11:31:05.448596
56	1	4	2026-05-18 11:31:18.543302
57	1	4	2026-05-18 11:31:31.651065
58	1	4	2026-05-18 11:31:44.750597
59	1	4	2026-05-18 11:31:57.849782
60	1	4	2026-05-18 11:32:10.993653
61	1	4	2026-05-18 11:32:24.118797
62	1	4	2026-05-18 11:32:37.273939
63	1	1	2026-05-18 11:32:50.233246
64	1	4	2026-05-18 11:32:50.418723
65	1	1	2026-05-18 11:33:03.343466
66	1	4	2026-05-18 11:33:03.548767
67	1	4	2026-05-18 11:33:16.6432
68	1	4	2026-05-18 11:33:29.724664
69	2	4	2026-05-18 11:33:30.033632
70	1	4	2026-05-18 11:33:42.863062
71	2	4	2026-05-18 11:33:43.175116
72	1	4	2026-05-18 11:33:55.988922
73	2	4	2026-05-18 11:33:56.272718
74	1	4	2026-05-18 11:34:09.064629
75	2	4	2026-05-18 11:34:09.332565
76	1	4	2026-05-18 11:34:22.151931
77	2	4	2026-05-18 11:34:22.464464
78	1	4	2026-05-18 11:34:35.227918
79	2	4	2026-05-18 11:34:35.599663
80	1	4	2026-05-18 11:34:48.353139
81	2	4	2026-05-18 11:34:48.698429
82	1	4	2026-05-18 11:35:01.486105
83	2	4	2026-05-18 11:35:01.818
84	1	4	2026-05-18 11:35:14.60957
85	2	4	2026-05-18 11:35:14.938734
86	1	4	2026-05-18 11:35:27.72425
87	2	4	2026-05-18 11:35:28.081562
88	1	4	2026-05-18 11:35:40.846532
89	2	4	2026-05-18 11:35:41.221729
90	1	4	2026-05-18 11:35:53.945569
91	2	4	2026-05-18 11:35:54.305503
92	1	4	2026-05-18 11:36:07.041157
93	2	4	2026-05-18 11:36:07.412862
94	1	4	2026-05-18 11:36:20.149238
95	2	4	2026-05-18 11:36:20.53733
96	1	4	2026-05-18 11:36:33.279614
97	2	4	2026-05-18 11:36:33.641307
98	1	4	2026-05-18 11:36:46.400737
99	2	4	2026-05-18 11:36:46.745577
100	1	4	2026-05-18 11:36:59.476719
101	2	4	2026-05-18 11:36:59.851021
102	1	4	2026-05-18 11:37:12.555537
103	2	4	2026-05-18 11:37:12.961877
104	1	4	2026-05-18 11:37:25.67194
105	2	4	2026-05-18 11:37:26.042466
106	1	4	2026-05-18 11:37:38.79899
107	2	4	2026-05-18 11:37:39.170755
108	1	4	2026-05-18 11:37:51.930792
109	2	4	2026-05-18 11:37:52.303973
110	1	4	2026-05-18 12:46:00.650971
111	2	4	2026-05-18 12:46:03.591939
112	1	4	2026-05-18 12:46:13.718372
113	2	4	2026-05-18 12:46:16.671949
114	1	4	2026-05-18 12:46:26.821655
115	2	4	2026-05-18 12:46:29.777733
116	1	4	2026-05-18 12:46:39.92846
117	1	4	2026-05-18 12:46:53.028222
118	2	2	2026-05-18 12:46:56.514475
119	1	4	2026-05-18 12:47:06.163361
120	2	2	2026-05-18 12:47:09.602904
121	1	4	2026-05-18 12:47:19.27774
122	2	2	2026-05-18 12:47:22.739649
123	1	4	2026-05-18 12:47:32.386057
124	2	2	2026-05-18 12:47:35.85899
125	1	4	2026-05-18 12:47:45.473039
126	2	2	2026-05-18 12:47:48.992123
127	1	4	2026-05-18 12:47:58.564651
128	1	4	2026-05-18 12:48:11.691572
129	1	4	2026-05-18 12:48:24.772325
130	1	4	2026-05-18 12:48:37.880156
131	1	4	2026-05-18 12:48:50.983304
\.


--
-- Data for Name: dispositivo_gps; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dispositivo_gps (id_dispositivo, device_id, id_residente, nombre, activo, fecha_alta) FROM stdin;
1	67108604	1	Celular Familia	t	2026-05-13 12:45:44.585905-06
\.


--
-- Data for Name: familiar; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.familiar (id_familiar, nombre, apellidos, email, telefono, activo, fecha_registro) FROM stdin;
1	Maria	Lopez Garcia	maria.lopez@familiar.com	8112345678	t	2026-05-13
2	Alejandro	Elias Sanchez	alejandro@demo.com	8342354678	t	2026-05-14
3	deigo	hikaru	deigo@demo.com	8998092345	t	2026-05-15
5	Lenin	Campos	lenin@demo.com	8341272908	t	2026-05-18
\.


--
-- Data for Name: familiar_residente; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.familiar_residente (id_vinculo, id_familiar, id_residente, parentesco, es_contacto_principal, fecha_inicio, fecha_fin) FROM stdin;
1	1	1	Hija	t	2026-05-13	\N
2	2	2	Hijo/a	t	2026-05-14	\N
3	3	3	Otro	t	2026-05-15	\N
5	5	3	Hermano/a	f	2026-05-18	\N
\.


--
-- Data for Name: gps_ping; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.gps_ping (id_ping, id_residente, latitud, longitud, registrado_en) FROM stdin;
1	3	20.6599000	-103.3493000	2026-04-20 12:34:11.952321
2	3	20.6601000	-103.3492000	2026-04-20 12:49:11.952321
3	3	20.6602000	-103.3491000	2026-04-20 13:04:11.952321
4	3	20.6610000	-103.3493000	2026-04-20 13:14:11.952321
\.


--
-- Data for Name: horario_medicamento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.horario_medicamento (id_horario, id_residente, id_medicamento, hora_programada, dosis, frecuencia, activo) FROM stdin;
2	2	4	08:00:00	20mg	Diaria	t
4	3	5	08:30:00	1000UI	Diaria	t
5	3	2	22:00:00	1mg	Condicional	t
6	4	3	09:00:00	10mg	Diaria	t
1	2	1	08:00:00	50mg	Diaria	t
3	1	3	09:00:00	10mg	Diaria	t
\.


--
-- Data for Name: lector_rfid; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.lector_rfid (id_lector, ubicacion, es_restringido, id_ala, id_sala) FROM stdin;
1	Entrada Principal	f	2	\N
2	Sala de Medicamentos	t	1	\N
3	Enfermeria	t	2	4
4	Cuarto de Suministros	t	1	\N
\.


--
-- Data for Name: limite_jardin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.limite_jardin (id_limite, descripcion, lat_min, lat_max, lon_min, lon_max) FROM stdin;
1	Perimetro jardin principal	20.6597000	20.6603000	-103.3496000	-103.3490000
\.


--
-- Data for Name: log_auditoria; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.log_auditoria (id_log, id_usuario, tabla_afectada, operacion, id_registro, ip_origen, timestamp_operacion) FROM stdin;
1	2	acceso_rfid	INSERT	2	\N	2026-04-20 13:19:11.952321
2	3	acceso_rfid	INSERT	3	\N	2026-04-20 13:19:11.952321
3	5	acceso_rfid	INSERT	4	\N	2026-04-20 13:19:11.952321
12	1	residente	UPDATE	6	\N	2026-04-20 13:32:00.258777
13	1	residente	UPDATE	6	\N	2026-04-20 13:32:19.065882
15	1	residente	UPDATE	6	\N	2026-04-23 14:06:30.894483
27	\N	usuario_sistema	INSERT	12	\N	2026-05-14 13:07:28.140397
28	\N	staff	UPDATE	12	\N	2026-05-14 13:07:48.198307
29	\N	residente	UPDATE	7	\N	2026-05-14 13:08:10.018713
30	\N	usuario_sistema	UPDATE	2	\N	2026-05-14 13:25:40.572043
31	\N	usuario_sistema	UPDATE	4	\N	2026-05-14 13:27:25.135432
32	\N	usuario_sistema	UPDATE	4	\N	2026-05-14 13:28:41.164628
33	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 13:28:56.160096
34	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 14:57:51.218897
35	1	acceso_rfid	INSERT	7	\N	2026-05-14 15:10:19.812567
36	1	acceso_rfid	INSERT	9	\N	2026-05-14 15:27:17.966646
37	6	acceso_rfid	INSERT	10	\N	2026-05-14 15:27:38.456332
38	4	acceso_rfid	INSERT	12	\N	2026-05-14 15:39:55.035432
39	6	acceso_rfid	INSERT	13	\N	2026-05-14 15:43:08.707511
40	\N	usuario_sistema	UPDATE	2	\N	2026-05-14 19:56:20.747304
41	\N	usuario_sistema	UPDATE	4	\N	2026-05-14 19:56:33.275002
42	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 20:19:03.585795
43	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 20:22:46.191552
44	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 20:57:59.189548
45	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 20:58:16.393786
46	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 21:08:50.053384
47	\N	usuario_sistema	UPDATE	2	\N	2026-05-14 21:09:10.863935
48	\N	usuario_sistema	UPDATE	4	\N	2026-05-14 21:09:11.884827
49	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 21:10:01.741914
50	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 21:10:44.266241
51	\N	usuario_sistema	UPDATE	2	\N	2026-05-14 21:10:44.803324
52	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 21:11:11.526704
53	\N	usuario_sistema	UPDATE	2	\N	2026-05-14 21:11:12.378545
54	\N	usuario_sistema	UPDATE	1	\N	2026-05-14 21:12:26.014635
55	\N	usuario_sistema	UPDATE	2	\N	2026-05-14 21:12:26.312346
58	\N	usuario_sistema	UPDATE	1	\N	2026-05-15 19:44:52.992586
59	\N	usuario_sistema	UPDATE	2	\N	2026-05-15 19:45:54.811103
60	\N	usuario_sistema	UPDATE	4	\N	2026-05-15 19:46:17.372331
61	\N	usuario_sistema	UPDATE	1	\N	2026-05-15 19:46:47.515693
62	\N	usuario_sistema	UPDATE	4	\N	2026-05-15 20:01:50.423005
63	\N	usuario_sistema	UPDATE	1	\N	2026-05-15 20:03:00.091099
64	\N	usuario_sistema	UPDATE	1	\N	2026-05-16 14:54:02.232204
66	1	staff	UPDATE	12	\N	2026-05-16 15:07:28.437779
67	\N	usuario_sistema	UPDATE	2	\N	2026-05-16 15:09:22.064626
68	\N	usuario_sistema	UPDATE	4	\N	2026-05-16 15:09:50.007332
70	\N	usuario_sistema	UPDATE	1	\N	2026-05-16 16:26:30.80797
71	\N	usuario_sistema	UPDATE	1	\N	2026-05-18 11:28:48.132059
72	\N	usuario_sistema	UPDATE	2	\N	2026-05-18 11:58:55.572124
73	\N	usuario_sistema	UPDATE	4	\N	2026-05-18 11:59:24.38438
74	\N	usuario_sistema	UPDATE	1	\N	2026-05-18 12:00:51.063193
75	\N	usuario_sistema	UPDATE	1	\N	2026-05-18 12:14:46.76838
76	\N	usuario_sistema	UPDATE	2	\N	2026-05-18 12:29:34.639683
77	\N	usuario_sistema	UPDATE	1	\N	2026-05-18 12:30:40.927834
78	\N	usuario_sistema	UPDATE	1	\N	2026-05-18 12:40:46.856001
79	\N	usuario_sistema	UPDATE	1	\N	2026-05-18 12:46:13.008123
\.


--
-- Data for Name: log_medicamento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.log_medicamento (id_log, id_horario, id_cuidador, fecha_administracion, incidente) FROM stdin;
1	1	4	2026-04-19 05:19:11.952321	\N
2	2	4	2026-04-19 05:19:11.952321	\N
3	3	4	2026-04-19 04:19:11.952321	\N
4	3	5	2026-04-20 04:19:11.952321	\N
5	4	6	2026-04-20 12:49:11.952321	\N
6	1	4	2026-05-14 16:01:53.858593	\N
7	2	4	2026-05-14 16:01:53.858593	\N
8	4	4	2026-05-14 17:01:53.858593	\N
9	3	5	2026-05-14 18:01:53.858593	\N
\.


--
-- Data for Name: medicamento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.medicamento (id_medicamento, nombre, descripcion, unidad) FROM stdin;
1	Sertralina	Antidepresivo ISRS	mg
2	Lorazepam	Ansolitico benzodiacepinico	mg
3	Memantina	Tratamiento demencia moderada	mg
4	Omeprazol	Protector gastrico	mg
5	Vitamina D3	Suplemento vitaminico	UI
\.


--
-- Data for Name: nfc_evento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.nfc_evento (id_evento, id_tag, id_staff, escaneado_en, id_log_med) FROM stdin;
1	1	6	2026-04-20 12:49:11.952321	5
\.


--
-- Data for Name: nfc_tag; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.nfc_tag (id_tag, codigo_tag, id_residente, descripcion) FROM stdin;
1	NFC-LM-103	3	Estacion de medicamentos - Hab. 103 (Luis Morales)
\.


--
-- Data for Name: pago; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pago (id_pago, id_familiar, id_residente, id_plan, monto, fecha_pago, metodo_pago, referencia, estado, periodo_mes, periodo_anio, concepto) FROM stdin;
1	1	1	1	38000.00	2026-02-16 16:24:16.155431	Transferencia SPEI	SPEI20250201	Completado	2	2025	Mensualidad Plan Bienestar — Feb 2026
2	1	1	1	38000.00	2026-03-16 16:24:16.155431	Tarjeta de crédito	CARD20250301	Completado	3	2025	Mensualidad Plan Bienestar — Mar 2026
3	1	1	1	38000.00	2026-04-16 16:24:16.155431	Transferencia SPEI	SPEI20250401	Completado	4	2025	Mensualidad Plan Bienestar — Apr 2026
4	1	1	1	38000.00	2026-05-11 16:24:16.155431	OXXO Pay	OXXO20250501	Completado	5	2025	Mensualidad Plan Bienestar — May 2026
5	1	1	1	38000.00	2026-01-16 16:25:03.969686	Transferencia SPEI	SPEI20250101	Completado	1	2025	Mensualidad Plan Bienestar
6	1	1	1	38000.00	2026-05-16 16:26:18.417443	Tarjeta de crédito	CARD202605165104	Completado	5	2026	Mensualidad Plan Bienestar — Mayo 2026
8	1	1	1	38000.00	2026-05-18 12:00:42.675221	Tarjeta de crédito	CARD202605180632	Completado	6	2026	Mensualidad Plan Bienestar — Junio 2026
\.


--
-- Data for Name: plan_residente; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.plan_residente (id_plan, id_residente, tipo_plan, monto_mensual, fecha_inicio, activo) FROM stdin;
1	1	Bienestar	38000.00	2024-03-01	t
2	2	Premium	55000.00	2024-01-15	t
3	3	Esencial	22500.00	2024-06-01	t
6	11	Premium	55000.00	2025-02-01	t
7	10	Esencial	22500.00	2025-01-10	t
8	4	Bienestar	38000.00	2024-09-01	t
\.


--
-- Data for Name: posicion_gps; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.posicion_gps (id_posicion, device_id, latitud, longitud, altitud, velocidad_kmh, rumbo, precision_m, bateria, ts_dispositivo, ts_servidor) FROM stdin;
1	67108604	25.6600111	-100.4203212	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.471071-06
2	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.537945-06
3	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.569082-06
4	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.599459-06
5	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.629903-06
6	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.656232-06
7	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.691614-06
8	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.723051-06
9	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.749025-06
10	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.776352-06
11	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.801974-06
12	67108604	25.6600111	-100.4203211	\N	\N	\N	\N	\N	\N	2026-05-13 13:03:25.828028-06
13	67108604	25.6600111	-100.4203211	674.08	\N	\N	11.71	55	2026-05-13 12:33:37.77-06	2026-05-13 13:12:18.473175-06
14	67108604	25.6600111	-100.4203211	674.08	\N	\N	11.71	55	2026-05-13 12:33:37.77-06	2026-05-13 13:12:18.540767-06
15	67108604	25.6600111	-100.4203211	674.08	\N	\N	11.71	55	2026-05-13 12:33:37.77-06	2026-05-13 13:12:19.928994-06
16	test	20.6600000	-103.3493000	\N	\N	\N	\N	\N	\N	2026-05-14 13:17:35.678642-06
17	67108604	25.6628556	-100.4203476	660.60	3.40	13.5	6.91	20	2026-05-13 16:33:07.001-06	2026-05-14 13:20:43.330994-06
18	67108604	25.6633989	-100.4208088	651.75	4.60	306.9	5.45	20	2026-05-13 16:34:13-06	2026-05-14 13:20:43.381362-06
19	67108604	25.6639312	-100.4212873	649.82	5.90	336.6	4.25	20	2026-05-13 16:35:12.001-06	2026-05-14 13:20:43.412875-06
20	67108604	25.6585294	-100.4384238	671.48	\N	\N	68.46	5	2026-05-13 18:40:42.375-06	2026-05-14 13:20:43.439587-06
21	67108604	25.6591192	-100.4382991	674.43	\N	\N	19.53	5	2026-05-13 18:45:46-06	2026-05-14 13:20:43.470165-06
22	67108604	25.6565318	-100.4386149	705.16	32.70	111.5	6.22	50	2026-05-13 20:50:21.015-06	2026-05-14 13:20:43.50082-06
23	67108604	25.6563705	-100.4378252	708.63	45.30	94.6	3.39	50	2026-05-13 20:50:28.01-06	2026-05-14 13:20:43.527884-06
24	67108604	25.6564420	-100.4370228	709.02	48.20	79.2	4.75	50	2026-05-13 20:50:34.006-06	2026-05-14 13:20:43.551259-06
25	67108604	25.6565805	-100.4362827	704.88	45.60	78.8	4.75	50	2026-05-13 20:50:40.004-06	2026-05-14 13:20:43.578341-06
26	67108604	25.6567108	-100.4354690	700.53	50.40	78.7	4.75	50	2026-05-13 20:50:46.003-06	2026-05-14 13:20:43.602983-06
27	67108604	25.6568282	-100.4347311	700.12	55.30	79.4	3.93	50	2026-05-13 20:50:51.002-06	2026-05-14 13:20:43.629962-06
28	67108604	25.6569610	-100.4339951	697.17	52.90	78.9	2.93	50	2026-05-13 20:50:56.001-06	2026-05-14 13:20:43.657158-06
29	67108604	25.6571187	-100.4331682	697.50	41.00	77.4	4.56	50	2026-05-13 20:51:08.001-06	2026-05-14 13:20:43.683657-06
30	67108604	25.6573171	-100.4323472	696.82	51.30	71.5	7.80	50	2026-05-13 20:51:14-06	2026-05-14 13:20:43.704957-06
31	67108604	25.6575792	-100.4315447	693.17	52.10	73.7	4.31	50	2026-05-13 20:51:20-06	2026-05-14 13:20:43.731797-06
32	67108604	25.6579172	-100.4298825	686.90	46.90	79.7	4.70	45	2026-05-13 20:51:32-06	2026-05-14 13:20:43.758666-06
33	67108604	25.6580591	-100.4290898	686.42	49.10	76.8	5.90	45	2026-05-13 20:51:38-06	2026-05-14 13:20:43.78197-06
34	67108604	25.6583328	-100.4283139	685.71	51.30	58.6	3.67	45	2026-05-13 20:51:44-06	2026-05-14 13:20:43.80615-06
35	67108604	25.6588884	-100.4276675	684.11	55.40	41.2	3.48	45	2026-05-13 20:51:50-06	2026-05-14 13:20:43.830691-06
36	67108604	25.6593900	-100.4271055	680.91	55.80	55.1	5.21	45	2026-05-13 20:51:55-06	2026-05-14 13:20:43.855107-06
37	67108604	25.6596933	-100.4264087	677.32	56.30	73.6	3.15	45	2026-05-13 20:52:00-06	2026-05-14 13:20:43.881091-06
38	67108604	25.6595492	-100.4248470	680.33	40.40	111.3	4.39	45	2026-05-13 20:52:12-06	2026-05-14 13:20:43.907059-06
39	67108604	25.6591148	-100.4241655	686.49	25.20	124.5	4.26	45	2026-05-13 20:52:25-06	2026-05-14 13:20:43.939746-06
40	67108604	25.6588937	-100.4234529	688.07	39.20	85.5	3.51	45	2026-05-13 20:52:32.999-06	2026-05-14 13:20:43.967801-06
41	67108604	25.6602854	-100.4233912	674.21	37.40	9.4	5.34	45	2026-05-13 20:52:54-06	2026-05-14 13:20:43.994441-06
42	67108604	25.6609722	-100.4232632	667.18	35.60	9.1	4.91	45	2026-05-13 20:53:02-06	2026-05-14 13:20:44.020092-06
43	67108604	25.6616766	-100.4231388	662.09	38.10	8.9	5.30	45	2026-05-13 20:53:09-06	2026-05-14 13:20:44.049833-06
44	67108604	25.6623844	-100.4230191	657.16	23.40	9.4	6.45	45	2026-05-13 20:53:19-06	2026-05-14 13:20:44.078889-06
45	67108604	25.6629650	-100.4226163	654.45	17.80	8.4	5.55	45	2026-05-13 20:53:37-06	2026-05-14 13:20:44.109633-06
46	67108604	25.6627087	-100.4215804	654.84	\N	\N	19.62	45	2026-05-13 20:56:24.27-06	2026-05-14 13:20:44.141734-06
47	67108604	25.6596607	-100.4178092	670.93	\N	\N	24.24	40	2026-05-13 21:05:00.882-06	2026-05-14 13:20:44.17266-06
48	67108604	25.6587640	-100.4124274	638.73	6.00	139.6	12.75	40	2026-05-13 21:12:58.14-06	2026-05-14 13:20:44.201876-06
49	67108604	25.6576611	-100.4096458	674.05	\N	\N	7.93	30	2026-05-14 12:50:26.56-06	2026-05-14 13:20:44.22791-06
50	67108604	25.6576611	-100.4096458	674.05	\N	\N	7.93	30	2026-05-14 12:50:26.56-06	2026-05-14 13:20:44.252148-06
51	67108604	25.6576611	-100.4096458	674.05	\N	\N	7.93	30	2026-05-14 12:50:26.56-06	2026-05-14 13:20:44.274844-06
52	67108604	25.6576611	-100.4096458	674.05	\N	\N	7.93	30	2026-05-14 12:50:26.56-06	2026-05-14 13:20:44.299285-06
53	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	30	2026-05-14 12:55:28.001-06	2026-05-14 13:20:44.323679-06
54	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	25	2026-05-14 12:55:28.001-06	2026-05-14 13:20:44.34759-06
55	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	25	2026-05-14 12:55:28.001-06	2026-05-14 13:20:44.370235-06
56	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	25	2026-05-14 12:55:28.001-06	2026-05-14 13:20:44.39338-06
57	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	25	2026-05-14 12:55:28.001-06	2026-05-14 13:20:45.840321-06
58	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	25	2026-05-14 12:55:28.001-06	2026-05-14 13:20:46.063802-06
59	67108604	25.6576689	-100.4096654	674.71	\N	\N	4.78	25	2026-05-14 12:55:28.001-06	2026-05-14 13:21:08.777646-06
60	67108604	25.6602161	-100.4171727	675.03	\N	\N	31.20	70	2026-05-14 15:58:01.762-06	2026-05-14 20:25:52.854242-06
61	67108604	25.6634288	-100.4215732	655.05	3.60	353.9	5.07	50	2026-05-14 17:49:49.001-06	2026-05-14 20:25:52.951478-06
62	67108604	25.6640924	-100.4210849	650.22	9.00	33.4	56.76	50	2026-05-14 17:50:30-06	2026-05-14 20:25:52.992639-06
63	67108604	25.6636432	-100.4217689	639.82	\N	\N	4.63	55	2026-05-14 17:56:15-06	2026-05-14 20:25:53.030282-06
64	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.063856-06
65	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.099687-06
66	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.132653-06
67	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.166992-06
68	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.206079-06
69	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.242167-06
70	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.294418-06
71	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.337767-06
72	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.381913-06
73	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.422381-06
74	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:53.461254-06
75	67108604	25.6636497	-100.4217926	648.12	\N	\N	31.10	85	2026-05-14 19:51:41.651-06	2026-05-14 20:25:54.872203-06
76	67108604	25.6586311	-100.4120703	671.92	3.10	231.7	6.44	70	2026-05-18 08:05:53.003-06	2026-05-18 11:49:22.237591-06
77	67108604	25.6589347	-100.4135238	666.44	4.00	303.4	7.40	70	2026-05-18 08:07:46-06	2026-05-18 11:49:22.340155-06
78	67108604	25.6591917	-100.4142222	666.15	4.50	306.2	7.25	65	2026-05-18 08:08:44.001-06	2026-05-18 11:49:22.493217-06
79	67108604	25.6596873	-100.4147347	665.91	9.70	328.5	6.07	65	2026-05-18 08:09:40-06	2026-05-18 11:49:22.683661-06
80	67108604	25.6601225	-100.4153097	669.68	4.90	315.7	6.03	65	2026-05-18 08:10:38.001-06	2026-05-18 11:49:22.76245-06
81	67108604	25.6603107	-100.4163691	667.55	\N	\N	31.18	65	2026-05-18 08:12:21.713-06	2026-05-18 11:49:22.92312-06
82	67108604	25.6601808	-100.4171216	695.45	\N	\N	22.98	65	2026-05-18 08:13:10.001-06	2026-05-18 11:49:23.09755-06
83	67108604	25.6597052	-100.4176556	676.20	4.70	203.9	7.12	65	2026-05-18 08:14:17.001-06	2026-05-18 11:49:23.196466-06
84	67108604	25.6594948	-100.4183790	675.47	4.90	275.1	7.89	65	2026-05-18 08:15:14.001-06	2026-05-18 11:49:23.32391-06
85	67108604	25.6600521	-100.4188073	671.34	5.70	16.8	5.94	65	2026-05-18 08:16:34.001-06	2026-05-18 11:49:23.424626-06
86	67108604	25.6607479	-100.4188282	664.77	5.70	353.9	8.56	60	2026-05-18 08:17:37.999-06	2026-05-18 11:49:23.505372-06
87	67108604	25.6613233	-100.4192329	665.82	6.20	343.7	7.38	60	2026-05-18 08:18:40.001-06	2026-05-18 11:49:23.616538-06
88	67108604	25.6617458	-100.4193779	664.19	\N	\N	7.06	60	2026-05-18 08:25:11.04-06	2026-05-18 11:49:23.671016-06
89	67108604	25.6633546	-100.4216001	656.44	4.20	337.5	4.69	45	2026-05-18 11:03:23-06	2026-05-18 11:49:23.759699-06
90	67108604	25.6637211	-100.4217431	651.37	\N	\N	18.41	35	2026-05-18 11:48:49.224-06	2026-05-18 11:49:23.883014-06
91	67108604	25.6637353	-100.4217062	648.89	\N	\N	2.00	35	2026-05-18 11:53:50-06	2026-05-18 11:53:45.052994-06
92	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:02:59.490348-06
93	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:03:06.969492-06
94	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:03:07.015754-06
95	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:03:08.454548-06
96	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:03:09.223052-06
97	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:03:09.66919-06
98	67108604	25.6634888	-100.4216355	652.82	\N	\N	19.34	30	2026-05-18 12:02:23.143-06	2026-05-18 12:03:10.181969-06
99	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:22.348376-06
100	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:22.739679-06
101	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:37.71791-06
102	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:41.36799-06
103	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:41.9849-06
104	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:42.304024-06
105	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:43.286792-06
106	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:44.094173-06
107	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:44.721277-06
108	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:47.829083-06
109	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:53.63506-06
110	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:53.725599-06
111	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:53.84366-06
112	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:54.471937-06
113	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:57.252871-06
114	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:57.343911-06
115	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:57.485437-06
116	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:03:58.180808-06
117	67108604	25.6632230	-100.4221395	651.00	\N	\N	42.17	30	2026-05-18 12:02:56.14-06	2026-05-18 12:04:14.963059-06
118	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:06:17.859101-06
119	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:06:17.908412-06
120	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:06:18.967959-06
121	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:06:19.016292-06
122	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:01.265312-06
123	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:02.793044-06
124	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:09.55534-06
125	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:09.60353-06
126	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:10.178444-06
127	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:10.392813-06
128	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:44.879837-06
129	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:45.013285-06
130	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:45.099013-06
131	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:45.141242-06
132	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:45.824943-06
133	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:46.016646-06
134	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:46.218098-06
135	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:46.743691-06
136	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:46.792296-06
137	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:46.837509-06
138	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:47.088501-06
139	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:47.233718-06
140	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:47.547946-06
141	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:07:47.876018-06
142	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:21:00.767674-06
143	67108604	25.6635853	-100.4216087	651.50	\N	\N	25.10	30	2026-05-18 12:05:03.203-06	2026-05-18 12:21:11.609255-06
\.


--
-- Data for Name: reporte_incidente; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reporte_incidente (id_incidente, id_residente, id_staff, fecha, tipo, descripcion, severidad) FROM stdin;
1	2	4	2026-04-20 13:19:11.952321	Agitacion	Alerta autom tica: puntaje de  nimo bajo (2/5) registrado por cuidador.	Media
2	2	4	2026-04-20 13:19:11.952321	Agitacion	Alerta autom tica: puntaje de  nimo bajo (1/5) registrado por cuidador.	Alta
3	3	6	2026-04-20 13:19:11.952321	Deambulacion	Alerta GPS: residente detectado fuera del per¡metro del jard¡n. Coords: (20.6610000, -103.3493000).	Alta
4	1	4	2026-04-15 13:19:11.952321	Caida	Residente resbalo al salir de la ducha. Sin lesiones graves, se notifico a familiar.	Media
5	4	6	2026-04-17 13:19:11.952321	Rechazo_Medicamento	Elena rechazo tomar la Memantina durante el desayuno. Se intento administrar con jugo.	Baja
6	2	4	2026-04-14 13:19:11.952321	Agitacion	Episodio de llanto prolongado durante visita familiar. Se ofrecio acompanamiento.	Baja
7	1	4	2026-05-14 13:27:45.290079	Deambulacion	Se mareo un poco pero ya se siente mejor.	Baja
8	1	4	2026-05-18 11:59:44.273397	Caida	bla\r\n	Media
\.


--
-- Data for Name: residente; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.residente (id_residente, nombre, apellidos, fecha_nacimiento, sexo, habitacion, diagnostico_principal, nivel_movilidad, contacto_emergencia, tel_emergencia, fecha_ingreso, activo) FROM stdin;
1	Roberto	Garcia Mendoza	1944-03-15	M	101	Demencia leve	Asistido	Rosa Garcia	3310001111	2026-04-20	t
2	Carmen	Vega Salinas	1949-07-22	F	102	Depresion mayor	Autonomo	Luis Vega	3310002222	2026-04-20	t
3	Luis	Morales Fuentes	1951-11-08	M	103	Ansiedad generalizada	Autonomo	Sofia Morales	3310003333	2026-04-20	t
4	Elena	Ruiz Castillo	1946-05-30	F	104	Deterioro cognitivo leve	Asistido	Marta Ruiz	3310004444	2026-04-20	t
10	Yuto	Hikaru	1955-10-23	M	111	bLA	Encamado	Yu Hikaru	9	2026-05-16	t
6	Alejandro	 Elias Sanchez	1960-12-23	M	110	Depresion Grave.	Autonomo	Karla Lopez Mandujano	812032039	2026-04-20	f
7	Diego	Mendoza	1960-10-23	M	112	Tiene esquizofrenia grado 2.\r\n	Encamado	Yesicca Maribel	83456789043	2026-04-23	f
11	Kira	Hanami	1950-02-10	F	\N	Demencia Senil en grado 1.	Autonomo	Take	03291201221	2026-05-16	t
\.


--
-- Data for Name: rol; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rol (id_rol, nombre_rol, nivel_acceso) FROM stdin;
1	Administrador	1
2	Terapeuta	2
3	Cuidador	3
\.


--
-- Data for Name: sala; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sala (id_sala, nombre, id_ala, capacidad) FROM stdin;
1	Sala de Terapia 1	1	3
2	Sala de Terapia 2	2	3
3	Sala Grupal	2	8
4	Consultorio Medico	2	2
\.


--
-- Data for Name: sesion_terapia; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sesion_terapia (id_sesion, id_residente, id_terapeuta, id_sala, fecha_sesion, tipo_sesion, duracion_min, asistio, notas) FROM stdin;
1	2	2	1	2026-04-17 13:19:11.952321	Individual	50	t	Paciente muestra signos de aislamiento social. Se ajustara plan terapeutico.
2	2	2	1	2026-04-19 13:19:11.952321	Individual	50	t	Empeoramiento notable del estado de animo. Posible ajuste de medicacion.
4	3	3	2	2026-04-19 13:19:11.952321	Individual	45	t	Practica tecnicas de respiracion. Progreso controlado.
5	4	3	2	2026-04-20 02:00:00	Individual	45	t	\N
7	1	2	4	2026-01-23 09:00:00	Individual	60	t	\N
8	2	2	4	2026-05-14 14:00:00	Individual	60	t	\N
9	1	2	1	2026-05-18 10:00:00	Grupal	60	t	\N
10	1	2	4	2026-05-19 13:00:00	Individual	60	t	\N
\.


--
-- Data for Name: staff; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.staff (id_staff, nombre, apellidos, especialidad, email, id_rol, activo, fecha_alta) FROM stdin;
1	Carlos	Medina Ortiz	Administrador	admin@asilo.mx	1	t	2026-04-20
2	Juan	Ramirez Soto	Psicologo Clinico	jramirez@asilo.mx	2	t	2026-04-20
3	Laura	Torres Vega	Geriatra	ltorres@asilo.mx	2	t	2026-04-20
4	Maria	Lopez Herrera	Cuidadora	mlopez@asilo.mx	3	t	2026-04-20
5	Pedro	Sanchez Ruiz	Cuidador	psanchez@asilo.mx	3	t	2026-04-20
6	Ana	Garcia Diaz	Cuidadora	agarcia@asilo.mx	3	t	2026-04-20
12	Diego	Fernandez	Psicologo	diego.fer@demo.com	2	t	2026-05-14
\.


--
-- Data for Name: turno; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.turno (id_turno, id_staff, id_ala, fecha, hora_inicio, hora_fin) FROM stdin;
1	4	1	2026-04-20	07:00:00	15:00:00
2	6	1	2026-04-20	07:00:00	15:00:00
3	5	2	2026-04-20	15:00:00	23:00:00
4	2	2	2026-04-20	09:00:00	17:00:00
5	3	2	2026-04-20	09:00:00	17:00:00
7	5	1	2026-05-14	07:00:00	15:00:00
8	6	2	2026-05-14	07:00:00	15:00:00
9	2	2	2026-05-14	08:00:00	16:00:00
10	4	3	2026-05-14	07:00:00	15:00:00
12	4	3	2026-05-18	07:00:00	15:00:00
13	4	1	2026-05-19	07:00:00	15:00:00
14	3	2	2026-05-19	07:00:00	15:00:00
\.


--
-- Data for Name: usuario_familiar; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_familiar (id_usuario, username, password_hash, id_familiar, activo, ultimo_login) FROM stdin;
1	familiar1	scrypt:32768:8:1$fZs9Pj9adQjJNfSg$c4935e09a70304b081399f1090af916b6cfa9bd41e155ebdbac76e21f739f4ec03f9f8743506950ba3613e64ff92ebb9179acbc2deacb150e695fa068665d5d7	1	t	\N
3	deigo	scrypt:32768:8:1$qzIycR1ZOg6CPtbz$98610dc91b3481dca124bdb908f7ae78ea6719f37f0e420595ba5ebfb43b41a89b01fba8e8a8fcfce558f91d242d3d633163d4d87216975b645c4e891c70e75d	3	t	\N
5	lenin	scrypt:32768:8:1$UJDivrrgxsl59NCL$2cb4866fb5ec8406e0d9600a27aa1e39932297b75267763a13287e10952f0a201511b60e869014a7140e6237fb2aabdc5dbc09aa70ed7629380a70ef6464148d	5	t	\N
2	alex	scrypt:32768:8:1$vft6AKU7tgTxl4I8$71653c1350f65d61ec2be1668dc7ff7178af30699f5001e6592fc17381ec143a35103cec4e4947021017aed7ed3815039b9c923cbbf62c844c8772a474467941	2	t	\N
\.


--
-- Data for Name: usuario_sistema; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_sistema (id_usuario, username, password_hash, id_staff, activo, ultimo_login) FROM stdin;
4	mlopez	scrypt:32768:8:1$P1wUnIlCmdn5LG5P$6473dd421aedc76961df77de51016837c05960b5bee54834d51aa3ca1d20f61ad1a81885f3df0eda72c83f6a7e562a355a9bc64bcc2d65d3af1cc3227c66c2e5	4	t	2026-05-18 11:59:24.38438
6	agarcia	scrypt:32768:8:1$rfRazTY3jiu7UhX0$f847a05a5905b9b2422babdc68386c3a65d5ebc6650a171d64dd2431175c94fecbe91c95292b3797efaf225a4ec9bbcf2b08298a0b083bff8397d6f82ba9df06	6	t	\N
3	ltorres	scrypt:32768:8:1$y5yMPKuPn1FeNd6n$30d56fce5462d0461404d7c1fbedd71727f35738006bf44d3391ef5d63af4da1c8c8ffa9cc47c17d8d4acfdc1e6797e047ac54b4e24c6680576809c5646ba0c6	3	t	\N
2	jramirez	scrypt:32768:8:1$9ZoPlhsOylarSQlw$51f1e070fe7a2817d704f5fa9a5cc49a094a2233d65e126dabf8bb46514c127039b56d0ac9b0a84994284c0d2fbe73eddf09a3b92feed62465a6417df1a7f193	2	t	2026-05-18 12:29:34.639683
5	psanchez	scrypt:32768:8:1$6BGp5IRn5yQhO1h3$92f5594a490eea42f2da47f1808438990ec0e2f2a32cae708b3d5a8a63e7dc412df4dacf5e002680f40ee0f11186c67a9a8ef70ffe02ade6f6f4e991656ebbfe	5	t	\N
1	admin	scrypt:32768:8:1$GsJJwcCMDrp73ncn$5bd09dfa813950391a90f4ac3f929a22bd799bafbe18494bb9dd3606a282153d18c846a439ce27d1d80a822136c429d60de3d73943fe944ac734eb5e159c422c	1	t	2026-05-18 12:46:13.008123
12	diego.fer	scrypt:32768:8:1$Z4csHy8xWLSBLUF1$3d7d01262f0dc796c56645e267e7317f6e6a24261b00b4394b05b6a0930319d4baa414529506aefbb4b224198309ebb85340458a3e891503dc250361d42b5d62	12	t	\N
\.


--
-- Data for Name: zona_gps; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.zona_gps (id_zona, nombre, descripcion, latitud, longitud, radio_m, tipo, color, activo, creado_en) FROM stdin;
1	Riesgo Aulas	\N	25.6617880	-100.4197280	100	segura	#22C55E	t	2026-05-14 20:27:47.287326-06
2	Riesgo CCU	\N	25.6602890	-100.4201250	80	peligrosa	#EF4444	t	2026-05-14 20:29:49.5285-06
3	ESTOA	\N	25.6634130	-100.4219270	10	peligrosa	#EF4444	f	2026-05-18 12:04:39.756222-06
4	ESTOA	\N	25.6632050	-100.4220720	20	peligrosa	#EF4444	f	2026-05-18 12:05:45.5527-06
5	ESTOA	\N	25.6636160	-100.4218300	50	peligrosa	#EF4444	t	2026-05-18 12:06:53.423088-06
\.


--
-- Name: acceso_rfid_id_acceso_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.acceso_rfid_id_acceso_seq', 13, true);


--
-- Name: actividad_id_actividad_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.actividad_id_actividad_seq', 4, true);


--
-- Name: ala_id_ala_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ala_id_ala_seq', 3, true);


--
-- Name: alerta_gps_id_alerta_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.alerta_gps_id_alerta_seq', 3, true);


--
-- Name: asignacion_id_asignacion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.asignacion_id_asignacion_seq', 12, true);


--
-- Name: asistencia_nfc_id_asistencia_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.asistencia_nfc_id_asistencia_seq', 8, true);


--
-- Name: beacon_id_beacon_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.beacon_id_beacon_seq', 4, true);


--
-- Name: checkin_estado_animo_id_checkin_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.checkin_estado_animo_id_checkin_seq', 11, true);


--
-- Name: deteccion_beacon_id_deteccion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deteccion_beacon_id_deteccion_seq', 131, true);


--
-- Name: dispositivo_gps_id_dispositivo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.dispositivo_gps_id_dispositivo_seq', 5, true);


--
-- Name: familiar_id_familiar_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.familiar_id_familiar_seq', 5, true);


--
-- Name: familiar_residente_id_vinculo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.familiar_residente_id_vinculo_seq', 5, true);


--
-- Name: gps_ping_id_ping_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.gps_ping_id_ping_seq', 4, true);


--
-- Name: horario_medicamento_id_horario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.horario_medicamento_id_horario_seq', 6, true);


--
-- Name: lector_rfid_id_lector_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.lector_rfid_id_lector_seq', 4, true);


--
-- Name: limite_jardin_id_limite_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.limite_jardin_id_limite_seq', 1, true);


--
-- Name: log_auditoria_id_log_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.log_auditoria_id_log_seq', 79, true);


--
-- Name: log_medicamento_id_log_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.log_medicamento_id_log_seq', 9, true);


--
-- Name: medicamento_id_medicamento_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.medicamento_id_medicamento_seq', 5, true);


--
-- Name: nfc_evento_id_evento_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.nfc_evento_id_evento_seq', 1, true);


--
-- Name: nfc_tag_id_tag_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.nfc_tag_id_tag_seq', 1, true);


--
-- Name: pago_id_pago_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pago_id_pago_seq', 8, true);


--
-- Name: plan_residente_id_plan_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.plan_residente_id_plan_seq', 8, true);


--
-- Name: posicion_gps_id_posicion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.posicion_gps_id_posicion_seq', 143, true);


--
-- Name: reporte_incidente_id_incidente_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reporte_incidente_id_incidente_seq', 8, true);


--
-- Name: residente_id_residente_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.residente_id_residente_seq', 11, true);


--
-- Name: rol_id_rol_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.rol_id_rol_seq', 3, true);


--
-- Name: sala_id_sala_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sala_id_sala_seq', 4, true);


--
-- Name: sesion_terapia_id_sesion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sesion_terapia_id_sesion_seq', 10, true);


--
-- Name: staff_id_staff_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.staff_id_staff_seq', 12, true);


--
-- Name: turno_id_turno_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.turno_id_turno_seq', 14, true);


--
-- Name: usuario_familiar_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuario_familiar_id_usuario_seq', 5, true);


--
-- Name: usuario_sistema_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuario_sistema_id_usuario_seq', 12, true);


--
-- Name: zona_gps_id_zona_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.zona_gps_id_zona_seq', 5, true);


--
-- Name: acceso_rfid acceso_rfid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acceso_rfid
    ADD CONSTRAINT acceso_rfid_pkey PRIMARY KEY (id_acceso);


--
-- Name: actividad actividad_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad
    ADD CONSTRAINT actividad_pkey PRIMARY KEY (id_actividad);


--
-- Name: ala ala_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ala
    ADD CONSTRAINT ala_pkey PRIMARY KEY (id_ala);


--
-- Name: alerta_gps alerta_gps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerta_gps
    ADD CONSTRAINT alerta_gps_pkey PRIMARY KEY (id_alerta);


--
-- Name: asignacion asignacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asignacion
    ADD CONSTRAINT asignacion_pkey PRIMARY KEY (id_asignacion);


--
-- Name: asistencia_nfc asistencia_nfc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencia_nfc
    ADD CONSTRAINT asistencia_nfc_pkey PRIMARY KEY (id_asistencia);


--
-- Name: beacon beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT beacon_pkey PRIMARY KEY (id_beacon);


--
-- Name: checkin_estado_animo checkin_estado_animo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_estado_animo
    ADD CONSTRAINT checkin_estado_animo_pkey PRIMARY KEY (id_checkin);


--
-- Name: deteccion_beacon deteccion_beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deteccion_beacon
    ADD CONSTRAINT deteccion_beacon_pkey PRIMARY KEY (id_deteccion);


--
-- Name: dispositivo_gps dispositivo_gps_device_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_device_id_key UNIQUE (device_id);


--
-- Name: dispositivo_gps dispositivo_gps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_pkey PRIMARY KEY (id_dispositivo);


--
-- Name: familiar familiar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar
    ADD CONSTRAINT familiar_pkey PRIMARY KEY (id_familiar);


--
-- Name: familiar_residente familiar_residente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar_residente
    ADD CONSTRAINT familiar_residente_pkey PRIMARY KEY (id_vinculo);


--
-- Name: gps_ping gps_ping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gps_ping
    ADD CONSTRAINT gps_ping_pkey PRIMARY KEY (id_ping);


--
-- Name: horario_medicamento horario_medicamento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_medicamento
    ADD CONSTRAINT horario_medicamento_pkey PRIMARY KEY (id_horario);


--
-- Name: lector_rfid lector_rfid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lector_rfid
    ADD CONSTRAINT lector_rfid_pkey PRIMARY KEY (id_lector);


--
-- Name: limite_jardin limite_jardin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.limite_jardin
    ADD CONSTRAINT limite_jardin_pkey PRIMARY KEY (id_limite);


--
-- Name: log_auditoria log_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_auditoria
    ADD CONSTRAINT log_auditoria_pkey PRIMARY KEY (id_log);


--
-- Name: log_medicamento log_medicamento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_medicamento
    ADD CONSTRAINT log_medicamento_pkey PRIMARY KEY (id_log);


--
-- Name: medicamento medicamento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medicamento
    ADD CONSTRAINT medicamento_pkey PRIMARY KEY (id_medicamento);


--
-- Name: nfc_evento nfc_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_evento
    ADD CONSTRAINT nfc_evento_pkey PRIMARY KEY (id_evento);


--
-- Name: nfc_tag nfc_tag_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_tag
    ADD CONSTRAINT nfc_tag_pkey PRIMARY KEY (id_tag);


--
-- Name: pago pago_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pago
    ADD CONSTRAINT pago_pkey PRIMARY KEY (id_pago);


--
-- Name: plan_residente plan_residente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_residente
    ADD CONSTRAINT plan_residente_pkey PRIMARY KEY (id_plan);


--
-- Name: posicion_gps posicion_gps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posicion_gps
    ADD CONSTRAINT posicion_gps_pkey PRIMARY KEY (id_posicion);


--
-- Name: reporte_incidente reporte_incidente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reporte_incidente
    ADD CONSTRAINT reporte_incidente_pkey PRIMARY KEY (id_incidente);


--
-- Name: residente residente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.residente
    ADD CONSTRAINT residente_pkey PRIMARY KEY (id_residente);


--
-- Name: rol rol_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT rol_pkey PRIMARY KEY (id_rol);


--
-- Name: sala sala_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sala
    ADD CONSTRAINT sala_pkey PRIMARY KEY (id_sala);


--
-- Name: sesion_terapia sesion_terapia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesion_terapia
    ADD CONSTRAINT sesion_terapia_pkey PRIMARY KEY (id_sesion);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id_staff);


--
-- Name: turno turno_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turno
    ADD CONSTRAINT turno_pkey PRIMARY KEY (id_turno);


--
-- Name: ala uq_ala_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ala
    ADD CONSTRAINT uq_ala_nombre UNIQUE (nombre);


--
-- Name: beacon uq_beacon_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT uq_beacon_nombre UNIQUE (nombre);


--
-- Name: familiar uq_familiar_email; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar
    ADD CONSTRAINT uq_familiar_email UNIQUE (email);


--
-- Name: medicamento uq_medicamento_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medicamento
    ADD CONSTRAINT uq_medicamento_nombre UNIQUE (nombre);


--
-- Name: nfc_tag uq_nfc_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_tag
    ADD CONSTRAINT uq_nfc_codigo UNIQUE (codigo_tag);


--
-- Name: residente uq_residente_habitacion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.residente
    ADD CONSTRAINT uq_residente_habitacion UNIQUE (habitacion);


--
-- Name: rol uq_rol_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT uq_rol_nombre UNIQUE (nombre_rol);


--
-- Name: sala uq_sala_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sala
    ADD CONSTRAINT uq_sala_nombre UNIQUE (nombre);


--
-- Name: staff uq_staff_email; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT uq_staff_email UNIQUE (email);


--
-- Name: usuario_familiar uq_usuario_familiar_username; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_familiar
    ADD CONSTRAINT uq_usuario_familiar_username UNIQUE (username);


--
-- Name: usuario_sistema uq_usuario_username; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_sistema
    ADD CONSTRAINT uq_usuario_username UNIQUE (username);


--
-- Name: familiar_residente uq_vinculo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar_residente
    ADD CONSTRAINT uq_vinculo UNIQUE (id_familiar, id_residente);


--
-- Name: usuario_familiar usuario_familiar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_familiar
    ADD CONSTRAINT usuario_familiar_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuario_sistema usuario_sistema_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_sistema
    ADD CONSTRAINT usuario_sistema_pkey PRIMARY KEY (id_usuario);


--
-- Name: zona_gps zona_gps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zona_gps
    ADD CONSTRAINT zona_gps_pkey PRIMARY KEY (id_zona);


--
-- Name: idx_acceso_rfid_lector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_acceso_rfid_lector ON public.acceso_rfid USING btree (id_lector, accedido_en DESC);


--
-- Name: idx_acceso_rfid_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_acceso_rfid_staff ON public.acceso_rfid USING btree (id_staff, accedido_en DESC);


--
-- Name: idx_asignacion_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_asignacion_residente ON public.asignacion USING btree (id_residente);


--
-- Name: idx_asignacion_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_asignacion_staff ON public.asignacion USING btree (id_staff);


--
-- Name: idx_checkin_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checkin_residente ON public.checkin_estado_animo USING btree (id_residente, fecha_registro DESC);


--
-- Name: idx_deteccion_beacon; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deteccion_beacon ON public.deteccion_beacon USING btree (id_beacon, detectado_en DESC);


--
-- Name: idx_deteccion_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deteccion_staff ON public.deteccion_beacon USING btree (id_staff, detectado_en DESC);


--
-- Name: idx_gps_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gps_residente ON public.gps_ping USING btree (id_residente, registrado_en DESC);


--
-- Name: idx_horario_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_horario_residente ON public.horario_medicamento USING btree (id_residente);


--
-- Name: idx_incidente_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidente_fecha ON public.reporte_incidente USING btree (fecha DESC);


--
-- Name: idx_incidente_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_incidente_residente ON public.reporte_incidente USING btree (id_residente);


--
-- Name: idx_log_medicamento_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_medicamento_fecha ON public.log_medicamento USING btree (fecha_administracion DESC);


--
-- Name: idx_log_medicamento_horario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_medicamento_horario ON public.log_medicamento USING btree (id_horario);


--
-- Name: idx_log_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_timestamp ON public.log_auditoria USING btree (timestamp_operacion DESC);


--
-- Name: idx_log_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_usuario ON public.log_auditoria USING btree (id_usuario);


--
-- Name: idx_nfc_evento_tag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nfc_evento_tag ON public.nfc_evento USING btree (id_tag, escaneado_en DESC);


--
-- Name: idx_pago_familiar; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pago_familiar ON public.pago USING btree (id_familiar, fecha_pago DESC);


--
-- Name: idx_pago_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pago_residente ON public.pago USING btree (id_residente, fecha_pago DESC);


--
-- Name: idx_sesion_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sesion_fecha ON public.sesion_terapia USING btree (fecha_sesion DESC);


--
-- Name: idx_sesion_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sesion_residente ON public.sesion_terapia USING btree (id_residente);


--
-- Name: idx_sesion_terapeuta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sesion_terapeuta ON public.sesion_terapia USING btree (id_terapeuta);


--
-- Name: idx_turno_ala; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_turno_ala ON public.turno USING btree (id_ala, fecha);


--
-- Name: idx_turno_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_turno_staff ON public.turno USING btree (id_staff, fecha);


--
-- Name: idx_vinculo_familiar; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vinculo_familiar ON public.familiar_residente USING btree (id_familiar);


--
-- Name: idx_vinculo_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vinculo_residente ON public.familiar_residente USING btree (id_residente);


--
-- Name: ix_alerta_pendiente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_alerta_pendiente ON public.alerta_gps USING btree (atendida, ts_alerta DESC);


--
-- Name: ix_asistencia_actividad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asistencia_actividad ON public.asistencia_nfc USING btree (id_actividad, ts_registro DESC);


--
-- Name: ix_asistencia_residente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asistencia_residente ON public.asistencia_nfc USING btree (id_residente, ts_registro DESC);


--
-- Name: ix_posicion_device_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_posicion_device_ts ON public.posicion_gps USING btree (device_id, ts_servidor DESC);


--
-- Name: uq_plan_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_plan_activo ON public.plan_residente USING btree (id_residente) WHERE (activo = true);


--
-- Name: acceso_rfid trg_after_acceso_rfid; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_after_acceso_rfid AFTER INSERT ON public.acceso_rfid FOR EACH ROW EXECUTE FUNCTION public.trg_auditoria_acceso_rfid();


--
-- Name: checkin_estado_animo trg_after_checkin_animo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_after_checkin_animo AFTER INSERT ON public.checkin_estado_animo FOR EACH ROW EXECUTE FUNCTION public.trg_alerta_animo_bajo();


--
-- Name: gps_ping trg_after_gps_ping; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_after_gps_ping AFTER INSERT ON public.gps_ping FOR EACH ROW EXECUTE FUNCTION public.trg_alerta_gps_fuera_limite();


--
-- Name: residente trg_after_residente; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_after_residente AFTER DELETE OR UPDATE ON public.residente FOR EACH ROW EXECUTE FUNCTION public.trg_auditoria_residente();


--
-- Name: staff trg_after_staff; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_after_staff AFTER DELETE OR UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.trg_auditoria_staff();


--
-- Name: usuario_sistema trg_after_usuario_sistema; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_after_usuario_sistema AFTER INSERT OR UPDATE ON public.usuario_sistema FOR EACH ROW EXECUTE FUNCTION public.trg_auditoria_usuario_sistema();


--
-- Name: log_medicamento trg_before_delete_log_medicamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_before_delete_log_medicamento BEFORE DELETE ON public.log_medicamento FOR EACH ROW EXECUTE FUNCTION public.trg_proteger_log_medicamento();


--
-- Name: residente trg_before_delete_residente; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_before_delete_residente BEFORE DELETE ON public.residente FOR EACH ROW EXECUTE FUNCTION public.trg_proteger_delete_residente();


--
-- Name: reporte_incidente trg_before_incidente; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_before_incidente BEFORE INSERT OR UPDATE ON public.reporte_incidente FOR EACH ROW EXECUTE FUNCTION public.trg_validar_incidente();


--
-- Name: sesion_terapia trg_before_sesion_terapia; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_before_sesion_terapia BEFORE INSERT OR UPDATE ON public.sesion_terapia FOR EACH ROW EXECUTE FUNCTION public.trg_validar_sesion_terapia();


--
-- Name: actividad actividad_id_staff_crea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad
    ADD CONSTRAINT actividad_id_staff_crea_fkey FOREIGN KEY (id_staff_crea) REFERENCES public.staff(id_staff) ON DELETE SET NULL;


--
-- Name: alerta_gps alerta_gps_id_zona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerta_gps
    ADD CONSTRAINT alerta_gps_id_zona_fkey FOREIGN KEY (id_zona) REFERENCES public.zona_gps(id_zona) ON DELETE SET NULL;


--
-- Name: asistencia_nfc asistencia_nfc_id_actividad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencia_nfc
    ADD CONSTRAINT asistencia_nfc_id_actividad_fkey FOREIGN KEY (id_actividad) REFERENCES public.actividad(id_actividad) ON DELETE RESTRICT;


--
-- Name: asistencia_nfc asistencia_nfc_id_residente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencia_nfc
    ADD CONSTRAINT asistencia_nfc_id_residente_fkey FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON DELETE CASCADE;


--
-- Name: asistencia_nfc asistencia_nfc_id_staff_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencia_nfc
    ADD CONSTRAINT asistencia_nfc_id_staff_fkey FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON DELETE SET NULL;


--
-- Name: dispositivo_gps dispositivo_gps_id_residente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_id_residente_fkey FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON DELETE SET NULL;


--
-- Name: acceso_rfid fk_acceso_lector; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acceso_rfid
    ADD CONSTRAINT fk_acceso_lector FOREIGN KEY (id_lector) REFERENCES public.lector_rfid(id_lector) ON UPDATE CASCADE;


--
-- Name: acceso_rfid fk_acceso_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acceso_rfid
    ADD CONSTRAINT fk_acceso_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: asignacion fk_asignacion_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asignacion
    ADD CONSTRAINT fk_asignacion_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: asignacion fk_asignacion_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asignacion
    ADD CONSTRAINT fk_asignacion_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: beacon fk_beacon_ala; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT fk_beacon_ala FOREIGN KEY (id_ala) REFERENCES public.ala(id_ala) ON UPDATE CASCADE;


--
-- Name: checkin_estado_animo fk_checkin_cuidador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_estado_animo
    ADD CONSTRAINT fk_checkin_cuidador FOREIGN KEY (id_cuidador) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: checkin_estado_animo fk_checkin_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_estado_animo
    ADD CONSTRAINT fk_checkin_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: deteccion_beacon fk_deteccion_beacon; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deteccion_beacon
    ADD CONSTRAINT fk_deteccion_beacon FOREIGN KEY (id_beacon) REFERENCES public.beacon(id_beacon) ON UPDATE CASCADE;


--
-- Name: deteccion_beacon fk_deteccion_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deteccion_beacon
    ADD CONSTRAINT fk_deteccion_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: gps_ping fk_gps_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gps_ping
    ADD CONSTRAINT fk_gps_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: horario_medicamento fk_horario_medicamento; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_medicamento
    ADD CONSTRAINT fk_horario_medicamento FOREIGN KEY (id_medicamento) REFERENCES public.medicamento(id_medicamento) ON UPDATE CASCADE;


--
-- Name: horario_medicamento fk_horario_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_medicamento
    ADD CONSTRAINT fk_horario_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: reporte_incidente fk_incidente_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reporte_incidente
    ADD CONSTRAINT fk_incidente_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: reporte_incidente fk_incidente_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reporte_incidente
    ADD CONSTRAINT fk_incidente_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: lector_rfid fk_lector_ala; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lector_rfid
    ADD CONSTRAINT fk_lector_ala FOREIGN KEY (id_ala) REFERENCES public.ala(id_ala) ON UPDATE CASCADE;


--
-- Name: lector_rfid fk_lector_sala; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lector_rfid
    ADD CONSTRAINT fk_lector_sala FOREIGN KEY (id_sala) REFERENCES public.sala(id_sala) ON UPDATE CASCADE;


--
-- Name: log_medicamento fk_log_cuidador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_medicamento
    ADD CONSTRAINT fk_log_cuidador FOREIGN KEY (id_cuidador) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: log_medicamento fk_log_horario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_medicamento
    ADD CONSTRAINT fk_log_horario FOREIGN KEY (id_horario) REFERENCES public.horario_medicamento(id_horario) ON UPDATE CASCADE;


--
-- Name: log_auditoria fk_log_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_auditoria
    ADD CONSTRAINT fk_log_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario_sistema(id_usuario) ON UPDATE CASCADE;


--
-- Name: nfc_evento fk_nfc_evento_log; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_evento
    ADD CONSTRAINT fk_nfc_evento_log FOREIGN KEY (id_log_med) REFERENCES public.log_medicamento(id_log) ON UPDATE CASCADE;


--
-- Name: nfc_evento fk_nfc_evento_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_evento
    ADD CONSTRAINT fk_nfc_evento_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: nfc_evento fk_nfc_evento_tag; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_evento
    ADD CONSTRAINT fk_nfc_evento_tag FOREIGN KEY (id_tag) REFERENCES public.nfc_tag(id_tag) ON UPDATE CASCADE;


--
-- Name: nfc_tag fk_nfc_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nfc_tag
    ADD CONSTRAINT fk_nfc_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: pago fk_pago_familiar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pago
    ADD CONSTRAINT fk_pago_familiar FOREIGN KEY (id_familiar) REFERENCES public.familiar(id_familiar) ON UPDATE CASCADE;


--
-- Name: pago fk_pago_plan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pago
    ADD CONSTRAINT fk_pago_plan FOREIGN KEY (id_plan) REFERENCES public.plan_residente(id_plan) ON UPDATE CASCADE;


--
-- Name: pago fk_pago_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pago
    ADD CONSTRAINT fk_pago_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: plan_residente fk_plan_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_residente
    ADD CONSTRAINT fk_plan_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: sala fk_sala_ala; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sala
    ADD CONSTRAINT fk_sala_ala FOREIGN KEY (id_ala) REFERENCES public.ala(id_ala) ON UPDATE CASCADE;


--
-- Name: sesion_terapia fk_sesion_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesion_terapia
    ADD CONSTRAINT fk_sesion_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- Name: sesion_terapia fk_sesion_sala; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesion_terapia
    ADD CONSTRAINT fk_sesion_sala FOREIGN KEY (id_sala) REFERENCES public.sala(id_sala) ON UPDATE CASCADE;


--
-- Name: sesion_terapia fk_sesion_terapeuta; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesion_terapia
    ADD CONSTRAINT fk_sesion_terapeuta FOREIGN KEY (id_terapeuta) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: staff fk_staff_rol; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT fk_staff_rol FOREIGN KEY (id_rol) REFERENCES public.rol(id_rol) ON UPDATE CASCADE;


--
-- Name: turno fk_turno_ala; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turno
    ADD CONSTRAINT fk_turno_ala FOREIGN KEY (id_ala) REFERENCES public.ala(id_ala) ON UPDATE CASCADE;


--
-- Name: turno fk_turno_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turno
    ADD CONSTRAINT fk_turno_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE;


--
-- Name: usuario_familiar fk_usuario_familiar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_familiar
    ADD CONSTRAINT fk_usuario_familiar FOREIGN KEY (id_familiar) REFERENCES public.familiar(id_familiar) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: usuario_sistema fk_usuario_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_sistema
    ADD CONSTRAINT fk_usuario_staff FOREIGN KEY (id_staff) REFERENCES public.staff(id_staff) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: familiar_residente fk_vinculo_familiar; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar_residente
    ADD CONSTRAINT fk_vinculo_familiar FOREIGN KEY (id_familiar) REFERENCES public.familiar(id_familiar) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: familiar_residente fk_vinculo_residente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.familiar_residente
    ADD CONSTRAINT fk_vinculo_residente FOREIGN KEY (id_residente) REFERENCES public.residente(id_residente) ON UPDATE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 8igI99TvM6iruaxktGaacONYzt4xpGsD0iJRpRfc1Umv2ae0GACvRfrQsXtTkuw

