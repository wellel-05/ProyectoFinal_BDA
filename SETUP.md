# Guía de instalación — ElderCare

## 1. Instalar PostgreSQL

Descargar e instalar **PostgreSQL 16** para Windows:
https://www.postgresql.org/download/windows/

- Dejar todos los valores por defecto (puerto **5432**)
- Establecer una contraseña para el superusuario `postgres` — se necesita en el paso 2
- Instalar **pgAdmin 4** cuando se solicite (opcional pero útil)

Verificar la instalación abriendo una terminal nueva:
```bash
psql --version
```
Si no se encuentra, agregar al PATH de Windows: `C:\Program Files\PostgreSQL\16\bin`

---

## 2. Crear la base de datos y el usuario

```bash
psql -U postgres -p 5432
```

Pegar dentro de psql:
```sql
CREATE DATABASE asilo_db;
CREATE USER equipo5proyfin WITH PASSWORD '123';
GRANT ALL PRIVILEGES ON DATABASE asilo_db TO equipo5proyfin;
\q
```

---

## 3. Ejecutar los scripts SQL

Navegar a la carpeta del proyecto y ejecutar los scripts **en este orden exacto**:

```bash
psql -U equipo5proyfin -d asilo_db -f DDL.sql
psql -U equipo5proyfin -d asilo_db -f gps_ddl.sql
psql -U equipo5proyfin -d asilo_db -f nfc_ddl.sql
psql -U equipo5proyfin -d asilo_db -f familiar_ddl.sql
psql -U equipo5proyfin -d asilo_db -f PROCEDURES.sql
psql -U equipo5proyfin -d asilo_db -f familiar_procedures.sql
psql -U equipo5proyfin -d asilo_db -f VIEWS_TRIGGERS.sql
psql -U equipo5proyfin -d asilo_db -f SEED.sql
```

Contraseña cuando se solicite: `123`

---

## 4. Instalar dependencias de Python

```bash
pip install -r requirements.txt
```

El proyecto usa **psycopg 3** (`psycopg[binary]`) y `psycopg-pool`. No instalar `psycopg2`.

---

## 5. Ejecutar la aplicación

```bash
python app.py
```

Abrir en el navegador: **http://127.0.0.1:8080**

---

## Credenciales de prueba

| Usuario   | Contraseña   | Portal        |
|-----------|--------------|---------------|
| admin     | admin123     | Administrador |
| jramirez  | terapeuta123 | Terapeuta     |
| mlopez    | cuidador123  | Cuidador      |
| familiar1 | familiar123  | Familiar      |

---

## Solución de problemas

| Problema                        | Solución                                                                  |
|---------------------------------|---------------------------------------------------------------------------|
| `psql` no encontrado            | Agregar `C:\Program Files\PostgreSQL\16\bin` al PATH de Windows           |
| Falla la contraseña en psql     | Agregar `-W`: `psql -U equipo5proyfin -d asilo_db -W -f DDL.sql`          |
| Error al instalar psycopg       | Ejecutar `pip install "psycopg[binary]" psycopg-pool`                     |
| Errores en SEED.sql al re-ejecutar | Los datos ya existen — los errores de clave duplicada se pueden ignorar |
