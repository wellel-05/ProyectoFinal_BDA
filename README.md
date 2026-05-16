# ElderCare — Sistema de Gestion de Asilo de Adultos Mayores

Sistema integral para la gestion clinica, operativa y de monitoreo de un asilo de adultos mayores con enfoque en salud mental. Integra tres portales diferenciados por rol, monitoreo IoT en tiempo real (GPS, NFC, RFID, Beacon BLE) y analítica con graficas interactivas.

**Equipo 5 — Bases de Datos Avanzadas — UDEM**

---

## Stack tecnologico

| Capa | Tecnologia |
|------|-----------|
| Backend | Python 3.11+ con Flask 3 |
| Base de datos principal | PostgreSQL 18 |
| Base de datos secundaria | MongoDB (eventos IoT, logs) |
| Frontend | Jinja2 + HTML5 / CSS3 / JavaScript |
| Graficas | Highcharts (5+ reportes dinamicos) |
| Seguridad | Flask-WTF CSRF + werkzeug scrypt |
| Driver DB | psycopg 3 (`psycopg[binary]`) |
| Pool conexiones | psycopg-pool `ConnectionPool` (min=2, max=10) |
| Config | python-dotenv |
| Tests | pytest + pytest-flask |

---

## Estructura del proyecto

```
proyectoFinalBDA-main/
├── app.py                    # Aplicacion Flask — 75+ rutas, 4 portales
├── .env                      # Variables de entorno (NO subir a git)
├── .env.example              # Plantilla de configuracion
├── requirements.txt          # Dependencias Python
│
├── DDL.sql                   # Esquema BD: 32 tablas, indices, constraints
├── PROCEDURES.sql            # 54+ procedimientos almacenados
├── VIEWS_TRIGGERS.sql        # 15 vistas + 10 triggers
├── SEED.sql                  # Datos de prueba (5 escenarios completos)
│
├── DOCUMENTACION_TECNICA.txt # Documentacion tecnica del sistema
├── DIAGRAMA_ER.drawio        # Diagrama Entidad-Relacion (draw.io)
├── generar_diagrama.py       # Script para regenerar el diagrama ER
│
├── logs/                     # Logs rotativos (auto-generado en runtime)
├── scripts/
│   ├── migrate_passwords.py  # Migra contrasenas texto plano -> scrypt
│   ├── export_mongodb.py     # Exporta eventos IoT a MongoDB
│   └── beacon_scanner.py     # Scanner BLE para deteccion de beacons
│
├── static/
│   ├── css/styles.css        # Sistema de diseno completo (CSS variables)
│   └── js/script.js          # Validacion client-side y helpers
│
└── templates/
    ├── base.html             # Layout principal con sidebar, CSRF, toasts
    ├── login.html            # Pantalla split-screen
    ├── errors/               # Paginas 404 y 500
    ├── admin/                # 14 plantillas: dashboard, residentes, staff,
    │                         #   medicamentos, turnos, IoT, RFID, NFC,
    │                         #   GPS, reportes, KPI, auditoria, familiares
    ├── terapeuta/            # 5 plantillas: dashboard, residentes,
    │                         #   sesiones, incidentes
    ├── cuidador/             # 6 plantillas: dashboard, residentes,
    │                         #   medicamentos, checkin, NFC
    ├── familiar/             # 3 plantillas: login, dashboard, residente
    └── nfc/                  # 2 plantillas: scan, confirmacion
```

---

## Base de datos

### Tablas (32)

| Modulo | Tablas |
|--------|--------|
| Personal | `staff`, `rol`, `usuario_sistema` |
| Residentes | `residente`, `asignacion` |
| Clinico | `sesion_terapia`, `sala`, `ala`, `checkin_estado_animo`, `reporte_incidente` |
| Medicamentos | `medicamento`, `horario_medicamento`, `log_medicamento` |
| Turnos | `turno` |
| IoT — NFC | `nfc_tag`, `nfc_evento`, `actividad`, `asistencia_nfc` |
| IoT — RFID | `lector_rfid`, `acceso_rfid` |
| IoT — Beacon | `beacon`, `deteccion_beacon` |
| IoT — GPS | `dispositivo_gps`, `posicion_gps`, `zona_gps`, `alerta_gps`, `limite_jardin` |
| Auditoria | `log_auditoria` |
| Familiares | `familiar`, `familiar_residente`, `usuario_familiar` |

### Procedimientos almacenados (54+)

Cubren todos los flujos del sistema: autenticacion, CRUD de residentes y staff, gestion clinica, medicamentos, turnos, IoT y reportes. Patron uniforme: `CALL sp_nombre(%s, ..., NULL, NULL)` con `OUT ok INT, OUT msg TEXT` o `INOUT resultado REFCURSOR`.

### Vistas (15)

`v_estado_gps_residentes`, `v_ubicacion_actual_staff`, `v_accesos_rfid_hoy`, `v_resumen_medicamentos_dia`, `v_incidentes_recientes`, `v_sesiones_proximas`, `v_animo_residentes_semana`, `v_carga_cuidadores`, `v_adherencia_terapeutica`, y otras.

### Triggers (10)

| Trigger | Evento | Accion |
|---------|--------|--------|
| `trg_checkin_auto_incidente` | INSERT checkin_estado_animo | Genera incidente si puntaje <= 2 |
| `trg_auditoria_baja_residente` | UPDATE residente | Registra en log_auditoria |
| `trg_auditoria_toggle_staff` | UPDATE staff | Registra cambio de estado |
| `trg_auditoria_acceso_rfid` | INSERT acceso_rfid | Registra accesos no autorizados |
| `trg_gps_alerta_perimetro` | INSERT gps_ping | Alerta si fuera del limite del jardin |
| + 5 adicionales de auditoria e integridad | | |

---

## Instalacion

### 1. Prerrequisitos

- Python 3.11+
- PostgreSQL 16+ (testeado con 18)
- MongoDB 6+ (opcional, para eventos IoT)

### 2. Clonar y configurar entorno virtual

```bash
git clone https://github.com/wellel-05/ProyectoFinal_BDA.git
cd ProyectoFinal_BDA

python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate     # Linux / macOS

pip install -r requirements.txt
```

### 3. Variables de entorno

```bash
copy .env.example .env
```

Editar `.env` con las credenciales de PostgreSQL. Nunca subir `.env` a git.

### 4. Crear base de datos y usuario

```sql
-- Ejecutar como superusuario en psql
CREATE DATABASE asilo_db;
CREATE USER equipo5proyfin WITH PASSWORD '123';
GRANT ALL PRIVILEGES ON DATABASE asilo_db TO equipo5proyfin;
```

### 5. Ejecutar scripts SQL en orden

```powershell
$env:PGPASSWORD = "tu_password_postgres"
$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

& $psql -U equipo5proyfin -d asilo_db -f DDL.sql
& $psql -U postgres       -d asilo_db -f PROCEDURES.sql
& $psql -U postgres       -d asilo_db -f VIEWS_TRIGGERS.sql
& $psql -U equipo5proyfin -d asilo_db -f SEED.sql
```

> `PROCEDURES.sql` y `VIEWS_TRIGGERS.sql` requieren el superusuario `postgres` para crear funciones con `SECURITY DEFINER`.

### 6. Ejecutar la aplicacion

```bash
python app.py
```

Acceso: [http://127.0.0.1:8080](http://127.0.0.1:8080)

---

## Usuarios de prueba

| Usuario | Contrasena | Rol | Portal |
|---------|-----------|-----|--------|
| admin | admin123 | Administrador | /admin/dashboard |
| jramirez | terapeuta123 | Terapeuta | /terapeuta/dashboard |
| ltorres | terapeuta123 | Terapeuta | /terapeuta/dashboard |
| mlopez | cuidador123 | Cuidador | /cuidador/dashboard |
| psanchez | cuidador123 | Cuidador | /cuidador/dashboard |
| agarcia | cuidador123 | Cuidador | /cuidador/dashboard |

> Contrasenas almacenadas con **scrypt** via `werkzeug.security.generate_password_hash`. Ningun dato sensible en texto plano.

---

## Pruebas

```bash
pytest tests/ -v
```

Los tests usan mocks para las funciones de base de datos — no requieren conexion activa a PostgreSQL.

---

## Funcionalidades por portal

### Portal Administrador

- **Dashboard** con KPIs en tiempo real (residentes activos, incidentes del dia, sesiones programadas, medicamentos pendientes, alertas IoT)
- **Gestion de residentes** — alta, edicion, baja logica, cambio de cuidador asignado, historial clinico completo
- **Gestion de staff** — registro, edicion, activacion/desactivacion, asignacion de roles
- **Medicamentos** — catalogo, horarios por residente, toggle activo/inactivo
- **Turnos** — registro y eliminacion de turnos por staff y ala
- **Monitoreo IoT**
  - GPS: mapa de posiciones, geocercas configurables, historial de alertas
  - Beacon BLE: deteccion de ubicacion de staff en tiempo real
  - RFID: control de acceso por lectores y alas, registro de accesos no autorizados
  - NFC: tags por residente, actividades, registro de asistencias
- **Reportes Highcharts** — evolucion de animo, incidentes por severidad, adherencia terapeutica, carga operativa, resumen IoT
- **Auditoria** — log completo de operaciones sensibles
- **Portal familiar** — registro de familiares, vinculacion con residentes

### Portal Terapeuta

- Residentes asignados con historial clinico y evolucion de animo (grafica 30 dias)
- Programacion de sesiones con deteccion de conflictos de horario
- Gestion de incidentes por residente
- Vista de sesiones de hoy

### Portal Cuidador

- Check-in de estado de animo (genera incidente automatico si puntaje <= 2)
- Medicamentos pendientes y administrados del dia
- Reporte manual de incidentes
- Escaneo NFC para registro de administracion de medicamentos y asistencia a actividades

### Portal Familiar

- Login independiente con credenciales propias
- Vista del estado actual del residente (animo, medicamentos, proximas sesiones)
- Historial de incidentes y sesiones (30 dias)

---

## Escenarios de prueba (SEED.sql)

Los datos de prueba usan `NOW()` y `CURRENT_DATE` relativos — siempre muestran informacion del dia actual.

| # | Escenario | Descripcion |
|---|-----------|-------------|
| 1 | Deterioro emocional | Carmen: 4 check-ins descendentes (4→3→2→1) → incidentes auto-generados por trigger |
| 2 | Multiples cuidadores | Roberto: Maria (turno matutino) + Pedro (turno nocturno), relacion N:M |
| 3 | NFC medicamento | Ana escanea tag de Luis → log transaccional + evento NFC |
| 4 | GPS perimetro | Luis: 3 pings dentro del jardin + 1 fuera → trigger genera alerta |
| 5 | RFID no autorizado | Pedro accede a Ala A sin turno asignado → trigger auditoria + sp_accesos_no_autorizados |

---

## Seguridad implementada

| Mecanismo | Descripcion |
|-----------|-------------|
| Hashing de contrasenas | scrypt via werkzeug (ninguna en texto plano) |
| CSRF protection | Flask-WTF en todos los formularios POST |
| Variables de entorno | Credenciales en `.env`, nunca en codigo fuente |
| RBAC | 4 niveles: Admin (1), Terapeuta (2), Cuidador (3), Familiar (4) |
| Audit log | Tabla `log_auditoria` registra operaciones sensibles con `set_config('app.id_usuario')` |
| Pool de conexiones | `psycopg-pool ConnectionPool` (min=2, max=10) — todas las conexiones devueltas con commit/rollback |
| Logging rotativo | `logs/eldercare.log` — rotacion a 5 MB, 3 backups |
| Errores genericos | Excepciones de BD no expuestas al usuario final |
| API IoT | Endpoint `/api/beacons` protegido con API key independiente de la sesion |

---

## Normalizacion

El esquema cumple **Tercera Forma Normal (3NF)**:

- **1NF** — todos los atributos son atomicos, sin grupos repetitivos
- **2NF** — sin dependencias parciales (todas las tablas tienen PK simple o compuesta bien definida)
- **3NF** — sin dependencias transitivas (datos del rol en tabla `rol` separada de `staff`, medicamento separado de `horario_medicamento`, etc.)

---

## Diagrama ER

El archivo `DIAGRAMA_ER.drawio` contiene el diagrama Entidad-Relacion completo con las 32 tablas organizadas por modulo:

- Catalogo (top): `rol`, `ala`, `sala`, `medicamento`, `limite_jardin`
- Core (centro): `staff`, `usuario_sistema`, `residente`, `asignacion`
- Clinico: `sesion_terapia`, `checkin_estado_animo`, `reporte_incidente`, `horario_medicamento`, `log_medicamento`
- IoT: `nfc_tag`, `nfc_evento`, `actividad`, `asistencia_nfc`, `lector_rfid`, `acceso_rfid`, `beacon`, `deteccion_beacon`
- GPS: `dispositivo_gps`, `posicion_gps`, `zona_gps`, `alerta_gps`
- Familiar: `familiar`, `familiar_residente`, `usuario_familiar`
- Auditoria: `log_auditoria`, `turno`

Para abrir: [draw.io](https://app.diagrams.net/) → File → Open from → Device → seleccionar `DIAGRAMA_ER.drawio`.

---

## Comandos utiles

```powershell
# Arrancar la app
python app.py

# Correr tests
pytest tests/ -v

# Re-ejecutar SQL (requiere superusuario para PROCEDURES y VIEWS_TRIGGERS)
$env:PGPASSWORD = "pwd_postgres"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d asilo_db -f PROCEDURES.sql
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d asilo_db -f VIEWS_TRIGGERS.sql

# Demo NFC sin hardware (abrir en navegador o telefono en la misma red)
# http://<IP_LOCAL>:8080/nfc/1

# Exportar eventos IoT a MongoDB
python scripts/export_mongodb.py

# Migrar contrasenas a scrypt (solo si hay usuarios con texto plano)
python scripts/migrate_passwords.py
```
