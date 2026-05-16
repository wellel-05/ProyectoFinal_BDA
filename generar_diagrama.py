# -*- coding: utf-8 -*-
"""Genera DIAGRAMA_ER.drawio con el schema completo de ElderCare."""

ROW_H = 25
HEADER_H = 30
TABLE_W = 220
KEY_W = 40

COLORS = {
    "blue":   ("#dae8fc", "#6c8ebf"),
    "green":  ("#d5e8d4", "#82b366"),
    "yellow": ("#fff2cc", "#d6b656"),
    "pink":   ("#f8cecc", "#b85450"),
    "purple": ("#e1d5e7", "#9673a6"),
    "gray":   ("#f5f5f5", "#666666"),
    "orange": ("#ffe6cc", "#d79b00"),
    "teal":   ("#d0e0e3", "#006eaf"),
}

TABLES = [
    # ── CATALOGOS — fila superior ──────────────────────────────────────────
    ("rol",               "rol",               "blue",   20,   20, [
        ("PK","id_rol","serial"), ("UK","nombre_rol","varchar"), ("","nivel_acceso","int")]),
    ("ala",               "ala",               "blue",  260,   20, [
        ("PK","id_ala","serial"), ("UK","nombre","varchar"), ("","piso","int"), ("","activa","boolean")]),
    ("sala",              "sala",              "blue",  500,   20, [
        ("PK","id_sala","serial"), ("UK","nombre","varchar"), ("FK","id_ala","int"), ("","capacidad","int")]),
    ("medicamento",       "medicamento",       "blue",  740,   20, [
        ("PK","id_medicamento","serial"), ("UK","nombre","varchar"), ("","descripcion","text"), ("","unidad","varchar")]),
    ("limite_jardin",     "limite_jardin",     "blue",  980,   20, [
        ("PK","id_limite","serial"), ("","lat_min","decimal"), ("","lat_max","decimal"),
        ("","lon_min","decimal"), ("","lon_max","decimal")]),

    # ── STAFF — columna izquierda ──────────────────────────────────────────
    ("staff",             "staff",             "green",  20,  165, [
        ("PK","id_staff","serial"), ("","nombre","varchar"), ("","apellidos","varchar"),
        ("","especialidad","varchar"), ("UK","email","varchar"), ("FK","id_rol","int"),
        ("","activo","boolean"), ("","fecha_alta","date")]),
    ("usuario_sistema",   "usuario_sistema",   "green",  20,  435, [
        ("PK","id_usuario","serial"), ("FK","id_staff","int"), ("UK","username","varchar"),
        ("","password_hash","varchar"), ("","activo","boolean")]),
    ("log_auditoria",     "log_auditoria",     "gray",   20,  630, [
        ("PK","id_log","bigserial"), ("FK","id_usuario","int"), ("","tabla_afectada","varchar"),
        ("","operacion","varchar"), ("","id_registro","int"),
        ("","timestamp_operacion","timestamp"), ("","ip_cliente","varchar")]),

    # ── OPERACIONALES — segunda columna ───────────────────────────────────
    ("turno",             "turno",             "yellow", 260,  165, [
        ("PK","id_turno","serial"), ("FK","id_staff","int"), ("FK","id_ala","int"),
        ("","fecha","date"), ("","hora_inicio","time"), ("","hora_fin","time")]),
    ("asignacion",        "asignacion",        "yellow", 260,  400, [
        ("PK","id_asignacion","serial"), ("FK","id_residente","int"), ("FK","id_staff","int"),
        ("","tipo_rol","varchar"), ("","es_principal","boolean"), ("","fecha_inicio","date")]),

    # ── RESIDENTE — columna central ────────────────────────────────────────
    ("residente",         "residente",         "green",  500,  165, [
        ("PK","id_residente","serial"), ("","nombre","varchar"), ("","apellidos","varchar"),
        ("","fecha_nacimiento","date"), ("","habitacion","varchar"),
        ("","diagnostico_principal","text"), ("","nivel_movilidad","varchar"), ("","activo","boolean")]),
    ("sesion_terapia",    "sesion_terapia",    "yellow", 500,  440, [
        ("PK","id_sesion","serial"), ("FK","id_residente","int"), ("FK","id_terapeuta","int"),
        ("FK","id_sala","int"), ("","fecha_sesion","date"), ("","tipo_sesion","varchar"), ("","asistio","boolean")]),

    # ── CLINICO — columna derecha-centro ──────────────────────────────────
    ("checkin_estado_animo","checkin_estado_animo","pink", 740, 165, [
        ("PK","id_checkin","serial"), ("FK","id_residente","int"), ("FK","id_cuidador","int"),
        ("","puntaje","int"), ("","fecha_registro","timestamp")]),
    ("reporte_incidente",  "reporte_incidente", "pink",  740,  365, [
        ("PK","id_incidente","serial"), ("FK","id_residente","int"), ("FK","id_staff","int"),
        ("","tipo","varchar"), ("","severidad","varchar"), ("","resuelto","boolean")]),
    ("horario_medicamento","horario_medicamento","pink",  740,  590, [
        ("PK","id_horario","serial"), ("FK","id_residente","int"), ("FK","id_medicamento","int"),
        ("","hora_administracion","time"), ("","dosis","varchar"), ("","activo","boolean")]),
    ("log_medicamento",    "log_medicamento",   "pink",  980,  590, [
        ("PK","id_log","bigserial"), ("FK","id_horario","int"), ("FK","id_cuidador","int"),
        ("","fecha_administracion","timestamp"), ("","metodo","varchar")]),

    # ── IoT GRUPO 1 — quinta columna ──────────────────────────────────────
    ("gps_ping",          "gps_ping",          "purple",1220,  165, [
        ("PK","id_ping","bigserial"), ("FK","id_residente","int"),
        ("","latitud","decimal"), ("","longitud","decimal"), ("","timestamp_servidor","timestamp")]),
    ("nfc_tag",           "nfc_tag",           "purple",1220,  365, [
        ("PK","id_tag","serial"), ("FK","id_residente","int"), ("UK","codigo_tag","varchar"), ("","activo","boolean")]),
    ("nfc_evento",        "nfc_evento",        "purple",1220,  540, [
        ("PK","id_evento","bigserial"), ("FK","id_tag","int"), ("FK","id_staff","int"),
        ("FK","id_log_med","bigint"), ("","timestamp_evento","timestamp")]),

    # ── IoT GRUPO 2 — sexta columna ───────────────────────────────────────
    ("lector_rfid",       "lector_rfid",       "purple",1480,   20, [
        ("PK","id_lector","serial"), ("","nombre","varchar"), ("FK","id_ala","int"),
        ("FK","id_sala","int"), ("","activo","boolean")]),
    ("acceso_rfid",       "acceso_rfid",       "purple",1480,  215, [
        ("PK","id_acceso","bigserial"), ("FK","id_lector","int"), ("FK","id_staff","int"),
        ("","timestamp_acceso","timestamp"), ("","acceso_concedido","boolean")]),
    ("beacon",            "beacon",            "purple",1480,  410, [
        ("PK","id_beacon","serial"), ("UK","nombre","varchar"), ("FK","id_ala","int"),
        ("","mac_address","varchar"), ("","activo","boolean")]),
    ("deteccion_beacon",  "deteccion_beacon",  "purple",1480,  605, [
        ("PK","id_deteccion","bigserial"), ("FK","id_beacon","int"), ("FK","id_staff","int"),
        ("","timestamp_deteccion","timestamp"), ("","rssi","int")]),

    # ── FAMILIAR — parte inferior izquierda ───────────────────────────────
    ("familiar",          "familiar",          "orange",  20, 1000, [
        ("PK","id_familiar","serial"), ("","nombre","varchar"), ("","apellidos","varchar"),
        ("UK","email","varchar"), ("","activo","boolean")]),
    ("familiar_residente","familiar_residente","orange",  20, 1195, [
        ("PK","id_vinculo","serial"), ("FK","id_familiar","int"), ("FK","id_residente","int"),
        ("","fecha_autorizacion","date")]),
    ("usuario_familiar",  "usuario_familiar",  "orange", 260, 1000, [
        ("PK","id_usuario","serial"), ("FK","id_familiar","int"), ("UK","username","varchar"),
        ("","password_hash","varchar"), ("","activo","boolean")]),

    # ── GPS AVANZADO — parte inferior centro ──────────────────────────────
    ("dispositivo_gps",   "dispositivo_gps",   "teal",  500,   900, [
        ("PK","id_dispositivo","serial"), ("FK","id_residente","int"),
        ("UK","device_id","varchar"), ("","activo","boolean")]),
    ("posicion_gps",      "posicion_gps",      "teal",  500,  1070, [
        ("PK","id_posicion","bigserial"), ("","device_id","varchar"),
        ("","latitud","decimal"), ("","longitud","decimal"), ("","ts_servidor","timestamp")]),
    ("zona_gps",          "zona_gps",          "teal",  740,   900, [
        ("PK","id_zona","serial"), ("","nombre","varchar"), ("","latitud_centro","decimal"),
        ("","longitud_centro","decimal"), ("","radio_metros","decimal"), ("","tipo_zona","varchar")]),
    ("alerta_gps",        "alerta_gps",        "teal",  740,  1120, [
        ("PK","id_alerta","bigserial"), ("FK","id_zona","int"), ("","device_id","varchar"),
        ("","timestamp_alerta","timestamp"), ("","atendida","boolean")]),

    # ── ACTIVIDADES NFC — parte inferior derecha ──────────────────────────
    ("actividad",         "actividad",         "purple", 980,   900, [
        ("PK","id_actividad","serial"), ("","nombre","varchar"), ("","tipo_actividad","varchar"),
        ("FK","id_staff_crea","int"), ("","activa","boolean")]),
    ("asistencia_nfc",    "asistencia_nfc",    "purple",1220,   900, [
        ("PK","id_asistencia","bigserial"), ("FK","id_residente","int"), ("FK","id_actividad","int"),
        ("FK","id_staff","int"), ("","timestamp_registro","timestamp"), ("","metodo","varchar")]),
]

RELATIONSHIPS = [
    ("sala",                "ala",               "1N"),
    ("staff",               "rol",               "1N"),
    ("usuario_sistema",     "staff",             "11"),
    ("asignacion",          "residente",         "1N"),
    ("asignacion",          "staff",             "1N"),
    ("turno",               "staff",             "1N"),
    ("turno",               "ala",               "1N"),
    ("sesion_terapia",      "residente",         "1N"),
    ("sesion_terapia",      "staff",             "1N"),
    ("sesion_terapia",      "sala",              "1N"),
    ("checkin_estado_animo","residente",         "1N"),
    ("checkin_estado_animo","staff",             "1N"),
    ("reporte_incidente",   "residente",         "1N"),
    ("reporte_incidente",   "staff",             "1N"),
    ("horario_medicamento", "residente",         "1N"),
    ("horario_medicamento", "medicamento",       "1N"),
    ("log_medicamento",     "horario_medicamento","1N"),
    ("log_medicamento",     "staff",             "1N"),
    ("gps_ping",            "residente",         "1N"),
    ("nfc_tag",             "residente",         "1N"),
    ("nfc_evento",          "nfc_tag",           "1N"),
    ("nfc_evento",          "staff",             "1N"),
    ("nfc_evento",          "log_medicamento",   "1N"),
    ("lector_rfid",         "ala",               "1N"),
    ("lector_rfid",         "sala",              "1N"),
    ("acceso_rfid",         "lector_rfid",       "1N"),
    ("acceso_rfid",         "staff",             "1N"),
    ("beacon",              "ala",               "1N"),
    ("deteccion_beacon",    "beacon",            "1N"),
    ("deteccion_beacon",    "staff",             "1N"),
    ("log_auditoria",       "usuario_sistema",   "1N"),
    ("familiar_residente",  "familiar",          "1N"),
    ("familiar_residente",  "residente",         "1N"),
    ("usuario_familiar",    "familiar",          "11"),
    ("dispositivo_gps",     "residente",         "1N"),
    ("alerta_gps",          "zona_gps",          "1N"),
    ("actividad",           "staff",             "1N"),
    ("asistencia_nfc",      "residente",         "1N"),
    ("asistencia_nfc",      "actividad",         "1N"),
    ("asistencia_nfc",      "staff",             "1N"),
]


def esc(s):
    return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")


def generate():
    p = []
    p.append('<?xml version="1.0" encoding="UTF-8"?>')
    p.append('<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" '
             'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
             'pageWidth="2339" pageHeight="1654" math="0" shadow="0">')
    p.append('  <root>')
    p.append('    <mxCell id="0" />')
    p.append('    <mxCell id="1" parent="0" />')

    nid = 100
    alias_id = {}

    row_sty = ("shape=tableRow;horizontal=0;startSize=0;swimlaneHead=0;swimlaneBody=0;"
               "fillColor=none;collapsible=0;dropTarget=0;"
               "points=[[0,0.5],[1,0.5]];portConstraint=eastwest;"
               "fontSize=11;top=0;left=0;right=0;bottom=1;")
    key_sty = ("shape=partialRectangle;connectable=0;fillColor=none;"
               "top=0;left=0;bottom=0;right=0;fontStyle=1;overflow=hidden;")
    val_sty = ("shape=partialRectangle;connectable=0;fillColor=none;"
               "top=0;left=0;bottom=0;right=0;overflow=hidden;")

    for (alias, display, color, x, y, fields) in TABLES:
        fill, stroke = COLORS[color]
        h = HEADER_H + len(fields) * ROW_H
        tid = nid; nid += 1
        alias_id[alias] = tid
        tsty = (f"shape=table;startSize={HEADER_H};container=1;collapsible=0;"
                f"childLayout=tableLayout;align=center;resizeLast=1;"
                f"fontSize=13;fontStyle=1;fillColor={fill};strokeColor={stroke};")
        p.append(f'    <mxCell id="{tid}" value="{esc(display)}" style="{tsty}" vertex="1" parent="1">')
        p.append(f'      <mxGeometry x="{x}" y="{y}" width="{TABLE_W}" height="{h}" as="geometry" />')
        p.append('    </mxCell>')

        for i, (key, fname, ftype) in enumerate(fields):
            ry = HEADER_H + i * ROW_H
            rid = nid; nid += 1
            kid = nid; nid += 1
            vid = nid; nid += 1
            p.append(f'    <mxCell id="{rid}" value="" style="{row_sty}" vertex="1" parent="{tid}">')
            p.append(f'      <mxGeometry y="{ry}" width="{TABLE_W}" height="{ROW_H}" as="geometry" />')
            p.append('    </mxCell>')
            p.append(f'    <mxCell id="{kid}" value="{esc(key)}" style="{key_sty}" vertex="1" parent="{rid}">')
            p.append(f'      <mxGeometry width="{KEY_W}" height="{ROW_H}" as="geometry">'
                     f'<mxRectangle width="{KEY_W}" height="{ROW_H}" as="alternateBounds" /></mxGeometry>')
            p.append('    </mxCell>')
            vw = TABLE_W - KEY_W
            p.append(f'    <mxCell id="{vid}" value="{esc(fname)} : {esc(ftype)}" style="{val_sty}" vertex="1" parent="{rid}">')
            p.append(f'      <mxGeometry x="{KEY_W}" width="{vw}" height="{ROW_H}" as="geometry">'
                     f'<mxRectangle width="{vw}" height="{ROW_H}" as="alternateBounds" /></mxGeometry>')
            p.append('    </mxCell>')

    for (src, tgt, rel) in RELATIONSHIPS:
        sid = alias_id.get(src)
        tid = alias_id.get(tgt)
        if not sid or not tid:
            continue
        eid = nid; nid += 1
        if rel == "11":
            esty = "edgeStyle=entityRelationEdgeStyle;endArrow=ERmandOne;startArrow=ERmandOne;fontSize=11;"
        else:
            esty = "edgeStyle=entityRelationEdgeStyle;endArrow=ERmandOne;startArrow=ERmany;fontSize=11;"
        p.append(f'    <mxCell id="{eid}" value="" style="{esty}" edge="1" source="{sid}" target="{tid}" parent="1">')
        p.append('      <mxGeometry relative="1" as="geometry" />')
        p.append('    </mxCell>')

    p.append('  </root>')
    p.append('</mxGraphModel>')
    return '\n'.join(p)


if __name__ == '__main__':
    xml = generate()
    with open('DIAGRAMA_ER.drawio', 'w', encoding='utf-8') as f:
        f.write(xml)
    print(f"Generado: DIAGRAMA_ER.drawio  ({len(TABLES)} tablas, {len(RELATIONSHIPS)} relaciones)")
