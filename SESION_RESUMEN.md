# ElderCare — Resumen de Sesión de Trabajo
**Fecha:** 2026-05-14 | **Demo:** ~2026-05-19 | **Equipo 5 — BDA UDEM**

---

## Lo que se arregló / implementó esta sesión

### Base de datos (SQL)

| Archivo | Cambio |
|---|---|
| `PROCEDURES.sql` | Agregados: `sp_ids_residentes_cuidador`, `sp_meds_pendientes_cuidador`, `sp_medicamentos_admin_hoy`, `sp_animo_bajo_cuidador`, `sp_sesiones_hoy_terapeuta` |
| `PROCEDURES.sql` | Corregido orden de OUT params en `sp_registrar_medicamento`, `sp_registrar_horario_medicamento`, `sp_registrar_turno` → ahora `OUT p_ok BOOLEAN, OUT p_msg TEXT` van PRIMERO (DROP + recrear) |
| `PROCEDURES.sql` | `sp_registrar_turno` mensaje cambiado a `'Turno agregado correctamente.'` |
| `PROCEDURES.sql` | `sp_toggle_horario_medicamento` tiene tres OUT: `p_ok, p_msg, p_activo` |

> Si un SP da "no se puede cambiar parámetros de salida": agregar `DROP PROCEDURE IF EXISTS sp_nombre(firma);` antes del CREATE.

### Backend (app.py)

- Corregidas todas las llamadas a `call_proc` que usaban solo el nombre del SP sin el `CALL` completo:
  ```python
  # Correcto:
  call_proc("CALL sp_registrar_medicamento(%s, %s, %s, NULL, NULL, NULL)", (nombre, desc, unidad))
  ```
- Ruta NFC `/nfc/<codigo_tag>`: cambiado `@login_required` → `@csrf.exempt`; corregida query (`horario_medicamento` / `id_horario` en lugar de `medicamento_diario` / `id_med_diario`); eliminado JOIN a `sala` que no existe en `residente`
- Toggle horario: `"CALL sp_toggle_horario_medicamento(%s, NULL, NULL, NULL)"` con el formato correcto
- Turno nuevo / eliminar: `"CALL sp_registrar_turno(%s,%s,%s,%s,%s, NULL, NULL, NULL)"` y `"CALL sp_eliminar_turno(%s, NULL, NULL)"`
- Sidebar admin: agregado `admin_asistencias` con icono `fa-mobile-screen`

### Frontend (templates)

- **`admin/turnos.html`** — corregido error `datetime.time` que usaba `.seconds` (atributo de timedelta); ahora usa `.hour` y `.minute`; botones de toggle cambiados a "Suspender" / "Reactivar" con texto legible
- **`admin/medicamentos.html`** — botón de toggle ahora muestra texto "Suspender" / "Reactivar"
- **`terapeuta/residente_detalle.html`** — corregido `map(attribute='puntaje')` → `map(attribute='puntaje_promedio')` que causaba error 500

### Scripts

- **`scripts/export_mongodb.py`** — corregido `UnicodeEncodeError` en Windows (reemplazados `→` y `—` por caracteres ASCII)

### Tipografía (cambio estético global)

Reemplazada `Cormorant Garamond` (serif con numerales old-style) por **`Plus Jakarta Sans`** en los 14 archivos de template. Los numerales ahora se ven modernos y alineados (lining/tabular), especialmente en KPIs y stat cards.

Archivos actualizados:
`base.html`, `login.html`, `index.html`, `familiar/login.html`, `errors/404.html`, `errors/500.html`, `admin/kpi.html`, `admin/iot.html`, `admin/reportes.html`, `admin/residente_detalle.html`, `familiar/dashboard.html`, `familiar/residente.html`, `cuidador/residentes.html`, `terapeuta/residente_detalle.html`

Nueva URL de Google Fonts en las páginas standalone (login, index, errors):
```
https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400&family=IBM+Plex+Sans:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400&display=swap
```

---

## Estado actual de la app

| Sección | Estado |
|---|---|
| Dashboard admin | ✅ Funciona |
| Dashboard terapeuta | ✅ Funciona (SPs verificados) |
| Dashboard cuidador | ✅ Funciona (SPs verificados) |
| Residentes CRUD | ✅ Funciona |
| Personal / Staff | ✅ Funciona |
| Medicamentos (horarios + catálogo + toggle) | ✅ Funciona |
| Turnos (nuevo + eliminar + toggle) | ✅ Funciona |
| Monitoreo IoT (beacon/GPS gráficas) | ✅ Funciona |
| Accesos RFID | ✅ Funciona |
| Tags NFC (admin) | ✅ Funciona |
| Actividades NFC (escaneo `/nfc/<id>`) | ✅ Funciona (iOS + Android, http sin SSL) |
| Asistencias NFC (admin) | ✅ En sidebar, ruta registrada |
| Reportes | ✅ Funciona |
| KPI | ✅ Funciona |
| GPS residentes | ✅ Funciona (demo con Traccar send location) |
| Familiares (portal completo) | ✅ Funciona |
| Auditoria | ✅ Funciona |
| MongoDB export | ✅ Funciona (`python scripts/export_mongodb.py`) |

---

## Lo que FALTA / pendiente para próxima sesión

### Alta prioridad (demo 2026-05-19)

- [ ] **Ensayo completo de demo** — recorrer todo el flujo: login admin → KPI → residente → sesión → NFC scan → beacon → GPS → familiar portal
- [ ] **Documentación técnica** — diagrama ER actualizado con tablas nuevas + documento Word/PDF con lista de SPs, vistas y triggers para la entrega

### Mejoras opcionales (si hay tiempo)

- [ ] **Seed data adicional** — asegurarse de que haya datos de hoy (turnos, checkins de ánimo, sesiones, accesos RFID) para que los dashboards no salgan vacíos en la demo
- [ ] **Formulario de alta de residente** — verificar end-to-end con el trigger de auditoría

---

## Beacons registrados en la demo

| ID | Nombre | MAC | Ubicación |
|---|---|---|---|
| 1 | Beacon Ala Norte | (MAC original) | Ala Norte |
| 4 | Beacon Ala Sur | DC:0D:30:1F:66:10 | Ala Sur |

```bash
# Correr scanner con filtro por MAC (dos terminales separadas)
python scripts/beacon_scanner.py monitor --beacon-id 1 --staff-id 1 --mac <MAC_BEACON_1>
python scripts/beacon_scanner.py monitor --beacon-id 4 --staff-id 1 --mac DC:0D:30:1F:66:10
```

---

## Comandos útiles para la demo

```bash
# Arrancar la app
python app.py

# Demo NFC sin hardware — abrir en navegador (o teléfono en misma red con http://)
http://<IP_LOCAL>:8080/nfc/1

# Exportar MongoDB
python scripts/export_mongodb.py

# Re-ejecutar SQL (siempre con postgres, no equipo5proyfin)
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d asilo_db -f "C:\Users\elias\proyectoFinalBDA-main\PROCEDURES.sql"
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d asilo_db -f "C:\Users\elias\proyectoFinalBDA-main\VIEWS_TRIGGERS.sql"
```

---

## Gotchas importantes a recordar

1. **`call_proc` siempre necesita un string `CALL sp_nombre(%s, ..., NULL, NULL)`** — nunca solo el nombre del SP
2. **OUT params en PostgreSQL: `OUT p_ok BOOLEAN, OUT p_msg TEXT` siempre primero** — si se cambia el orden hay que hacer DROP antes de CREATE
3. **NFC en iPhone solo funciona con `http://`** — no `https://`; la IP local de la laptop en la misma red
4. **Re-ejecutar SQL con usuario `postgres`** — `equipo5proyfin` no tiene DDL
5. **Reiniciar Flask después de cambios en la DB** — el pool de conexiones puede quedar en estado de error
6. **`call_refcursor` espera cursor llamado `resultado`** — el SP debe hacer `OPEN resultado FOR ...`
7. **`DROP VIEW IF EXISTS` antes de recrear vistas** — PostgreSQL no permite cambiar columnas con `CREATE OR REPLACE VIEW`
