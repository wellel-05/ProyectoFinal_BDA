# ElderCare — Sistema de Gestion de Asilo

Sistema integral para la gestion de un asilo de adultos mayores con enfoque en salud mental. Integra gestion clinica, monitoreo IoT (GPS, NFC, RFID, Beacon) y operaciones administrativas con 3 portales diferenciados por rol.

**Equipo 5 — Bases de Datos Avanzadas — UDEM**

---

## Stack tecnologico

| Capa | Tecnologia |
|------|-----------|
| Backend | Python 3.11+ + Flask 3 |
| Base de datos | PostgreSQL 16 |
| Frontend | Jinja2 + HTML5/CSS3/JavaScript |
| Seguridad | Flask-WTF CSRF + werkzeug scrypt |
| Pool DB | psycopg2 ThreadedConnectionPool |
| Config | python-dotenv |
| Tests | pytest + pytest-flask |

---

## Estructura del proyecto

```
proyectoFinalBDA-main/
├── app.py                  # Aplicacion Flask (45 rutas, 3 portales)
├── .env                    # Variables de entorno — NO incluir en git
├── .env.example            # Plantilla de configuracion
├── requirements.txt        # Dependencias Python
│
├── DDL.sql                 # Esquema BD: 22 tablas, indices, constraints
├── PROCEDURES.sql          # 30+ procedimientos almacenados
├── VIEWS_TRIGGERS.sql      # 15+ vistas y triggers
├── SEED.sql                # Datos de prueba (6 usuarios, 4 residentes, 5 escenarios)
│
├── logs/                   # Logs rotativos (auto-generado en runtime)
│
├── static/
│   ├── css/styles.css      # Sistema de diseño completo (CSS variables)
│   └── js/script.js        # Validacion client-side y Chart.js
│
├── templates/
│   ├── base.html           # Layout principal con sidebar, CSRF, toasts
│   ├── login.html          # Pantalla split-screen
│   ├── errors/             # Paginas 404 y 500
│   ├── admin/              # 8 plantillas: dashboard, residentes, staff, IoT, RFID, reportes, auditoria
│   ├── terapeuta/          # 6 plantillas: dashboard, residentes, sesiones, incidentes
│   └── cuidador/           # 6 plantillas: dashboard, residentes, medicamentos, checkin, NFC
│
└── tests/
    ├── conftest.py         # Fixtures pytest
    ├── test_auth.py        # Tests de autenticacion y RBAC
    └── test_admin.py       # Tests del portal administrador
```

---

## Instalacion

### 1. Prerrequisitos

- Python 3.11+
- PostgreSQL 16

### 2. Clonar y configurar entorno virtual

```bash
git clone <repo-url>
cd proyectoFinalBDA-main

python -m venv venv

# Windows
venv\Scripts\activate

# Linux / macOS
source venv/bin/activate

pip install -r requirements.txt
```

### 3. Configurar variables de entorno

```bash
cp .env.example .env
```

Edita `.env` con tus credenciales de PostgreSQL. El archivo `.env` nunca debe subirse a git.

### 4. Crear base de datos

```sql
-- Ejecutar como superusuario en psql
CREATE DATABASE asilo_db;
CREATE USER equipo5proyfin WITH PASSWORD '123';
GRANT ALL PRIVILEGES ON DATABASE asilo_db TO equipo5proyfin;
```

### 5. Ejecutar scripts SQL en orden

```bash
psql -U equipo5proyfin -d asilo_db -f DDL.sql
psql -U equipo5proyfin -d asilo_db -f PROCEDURES.sql
psql -U equipo5proyfin -d asilo_db -f VIEWS_TRIGGERS.sql
psql -U equipo5proyfin -d asilo_db -f SEED.sql
```

### 6. Ejecutar la aplicacion

```bash
python app.py
```

Acceso: [http://127.0.0.1:8080](http://127.0.0.1:8080)

---

## Usuarios de prueba

| Usuario | Contraseña | Rol | Acceso |
|---------|-----------|-----|--------|
| admin | admin123 | Administrador | Portal Admin |
| jramirez | terapeuta123 | Terapeuta | Portal Terapeuta |
| ltorres | terapeuta123 | Terapeuta | Portal Terapeuta |
| mlopez | cuidador123 | Cuidador | Portal Cuidador |
| psanchez | cuidador123 | Cuidador | Portal Cuidador |
| agarcia | cuidador123 | Cuidador | Portal Cuidador |

> Contraseñas almacenadas con **scrypt** via `werkzeug.security.generate_password_hash`

---

## Pruebas

```bash
pytest tests/ -v
```

Los tests usan mocks para las funciones de base de datos — no requieren conexion activa a PostgreSQL.

---

## Seguridad implementada

- **Hashing de contraseñas** — scrypt via werkzeug (ninguna contraseña en texto plano)
- **CSRF protection** — Flask-WTF en todos los formularios POST (inyeccion automatica via JS en `base.html`)
- **Variables de entorno** — Credenciales en `.env`, nunca en codigo fuente
- **RBAC** — 3 niveles de acceso: Admin (1), Terapeuta (2), Cuidador (3)
- **Audit log** — Tabla `log_auditoria` registra todas las operaciones sensibles
- **Pool de conexiones** — `ThreadedConnectionPool` (min=2, max=10)
- **Logging rotativo** — `logs/eldercare.log` con rotacion a 5MB (3 backups)
- **Mensajes de error genericos** — Excepciones de BD no expuestas al usuario

---

## Funcionalidades

### Portal Administrador
- Gestion completa de residentes (CRUD + baja logica)
- Gestion de staff con activacion/desactivacion
- Monitoreo IoT: GPS en jardin, beacons, lectores RFID
- Reportes: evolucion de animo, incidentes por severidad, adherencia terapeutica, carga operativa, resumen IoT
- Auditoria completa de operaciones

### Portal Terapeuta
- Vista de residentes asignados con historial clinico
- Programacion de sesiones con deteccion de conflictos
- Gestion de incidentes
- Seguimiento de evolucion de animo (30 dias)

### Portal Cuidador
- Check-in de estado de animo (auto-genera incidente si puntaje ≤ 2)
- Medicamentos pendientes y administrados del dia
- Reporte manual de incidentes
- Escaneo NFC para registro de medicamentos

---

## Escenarios de prueba (SEED.sql)

| # | Escenario | Descripcion |
|---|-----------|-------------|
| 1 | Deterioro emocional | Carmen: 4 check-ins descendentes → auto-incidentes |
| 2 | Multiples cuidadores | Roberto: Maria (matutino) + Pedro (nocturno) N:M |
| 3 | NFC medicamento | Ana escanea tag de Luis → log transaccional |
| 4 | GPS perimetro | Luis: 3 pings dentro + 1 fuera → trigger alerta |
| 5 | RFID no autorizado | Pedro accede a Ala A sin turno → auditoria |
