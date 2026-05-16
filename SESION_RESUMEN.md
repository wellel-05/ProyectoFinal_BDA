# ElderCare — Resumen de Sesión de Trabajo
**Fecha:** 2026-05-15 | **Demo:** 2026-05-19 | **Equipo 5 — BDA UDEM**

---

## Sesión 2026-05-15

### Migración psycopg2 → psycopg 3

Driver de BD migrado completamente de `psycopg2` a `psycopg` (v3) + `psycopg-pool`.

| Archivo | Cambio |
|---|---|
| `app.py` imports | `import psycopg` + `from psycopg.rows import dict_row` + `from psycopg_pool import ConnectionPool` |
| `app.py` pool | `ConnectionPool(min_size=2, max_size=10, kwargs=DB_CONFIG, open=True)` |
| `app.py` cursores | `row_factory=dict_row` en lugar de `cursor_factory=RealDictCursor` en todos los cursores |
| `app.py` call_refcursor | Eliminados `cur.execute('BEGIN')` / `cur.execute('COMMIT')` → `conn.commit()` / `conn.rollback()` nativos |
| `requirements.txt` | `psycopg[binary]>=3.3.0` + `psycopg-pool>=3.3.0` (reemplaza `psycopg2-binary`) |
| `scripts/migrate_passwords.py` | `import psycopg` + `psycopg.connect(...)` |
| `README.md` | Stack table + security section actualizados |
| `SETUP.md` | Instrucciones de instalación y troubleshooting actualizados |
| `DOCUMENTACION_TECNICA.txt` | Driver DB actualizado |

### Correcciones de connection pool (psycopg3)

| Función / Ruta | Bug | Fix |
|---|---|---|
| `query()` | Sin commit después de SELECT → conexiones en INTRANS al regresar al pool → warnings | Agregado `conn.commit()` en path feliz, `conn.rollback()` en except |
| `call_proc()` | `fetchone()` después de `commit()` | Reordenado: `fetchone()` → `commit()` |
| `nfc_confirmar` | Connection leak: faltaba `finally: release_db(conn)` | Agregado finally block |
| `admin_actividad_nueva` | Connection leak: faltaba `finally: release_db(conn)` | Agregado finally block |
| `admin_actividad_toggle` | Connection leak: faltaba `finally: release_db(conn)` | Agregado finally block |
| `admin_actividad_delete` | Connection leak: faltaba `finally: release_db(conn)` | Agregado finally block |

Todos los `get_db()` tienen su `release_db()` correspondiente (19/19). Los warnings `rolling back returned connection` desaparecen con el commit en `query()`.

### Documentación generada

- `DOCUMENTACION_TECNICA.txt` — documento técnico profesional de 10 secciones
- `DIAGRAMA_ER.drawio` — diagrama nativo draw.io (32 tablas, 40 relaciones, layout en columnas para minimizar cruces)
- `generar_diagrama.py` — script Python para regenerar el diagrama
- `ENSAYO_DEMO.txt` — guía de ensayo completa: presencial 10 min + video, cobre todos los ítems de la rúbrica

---

## Lo que se arregló / implementó en sesión anterior (2026-05-14)

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

## Lo que FALTA / pendiente para demo (2026-05-19)

### Alta prioridad

- [ ] **Ensayo cronometrado** — recorrer el flujo completo con timer: login admin → KPI → residente → sesión → NFC scan → beacon → GPS → familiar portal (10 min presencial)
- [ ] **Asignar segmentos de la presentación** a cada integrante del equipo (ver ENSAYO_DEMO.txt)
- [ ] **Video** — grabar funcionalidades que no caben en los 10 min presenciales (ERD, DDL, portal terapeuta/cuidador completo, familiar, audit)
- [ ] **Subir video a YouTube** antes del 2026-05-19

### Opcional (si hay tiempo)

- [ ] **Seed data adicional** — el SEED.sql usa `NOW()` / `CURRENT_DATE` relativos, así que es relativo a cuando se corre. OK para la demo.
- [ ] **README técnico** (5% rúbrica) — el README.md ya existe, verificar que cubra todos los puntos de la rúbrica

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
8. **psycopg 3: `row_factory=dict_row` en el cursor, NO `cursor_factory=RealDictCursor`** — ese era el patron de psycopg2
9. **psycopg 3: NO usar `cur.execute('BEGIN')` ni `cur.execute('COMMIT')`** — psycopg3 gestiona las transacciones con `conn.commit()` / `conn.rollback()`
10. **psycopg 3: siempre hacer `conn.commit()` después de SELECT** — si no, la conexión regresa al pool en estado `INTRANS` y aparecen los warnings `rolling back returned connection`
11. **Todo `get_db()` debe tener su `release_db(conn)` en el `finally`** — si no, el pool se agota y la app se cuelga
