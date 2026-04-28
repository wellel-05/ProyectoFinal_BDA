# Setup Guide — proyectoFinalBDA

## 1. Install PostgreSQL

Download and install **PostgreSQL 16** for Windows:
https://www.postgresql.org/download/windows/

- Keep all defaults (port **5432**)
- Set a password for the `postgres` superuser — you'll need it in step 2
- Install **pgAdmin 4** when prompted (optional but useful)

After install, open a new terminal and verify:
```bash
psql --version
```
If not found, add to Windows PATH: `C:\Program Files\PostgreSQL\16\bin`

---

## 2. Create Database and User

```bash
psql -U postgres -p 5432
```

Paste inside psql:
```sql
CREATE DATABASE asilo_db;
CREATE USER equipo5proyfin WITH PASSWORD '123';
GRANT ALL PRIVILEGES ON DATABASE asilo_db TO equipo5proyfin;
\q
```

---

## 3. Run SQL Scripts

Navigate to this folder, then run the 4 scripts **in this exact order**:

```bash
psql -U equipo5proyfin -d asilo_db -f DDL.sql
psql -U equipo5proyfin -d asilo_db -f PROCEDURES.sql
psql -U equipo5proyfin -d asilo_db -f VIEWS_TRIGGERS.sql
psql -U equipo5proyfin -d asilo_db -f SEED.sql
```

Password when prompted: `123`

---

## 4. Install Python Dependencies

```bash
pip install flask psycopg2-binary werkzeug
```

---

## 5. Run the App

```bash
python app.py
```

Open: **http://127.0.0.1:8080**

---

## Test Credentials

| Username  | Password     | Portal        |
|-----------|--------------|---------------|
| admin     | admin123     | Administrador |
| jramirez  | terapeuta123 | Terapeuta     |
| mlopez    | cuidador123  | Cuidador      |

---

## Troubleshooting

| Problem                   | Fix                                                               |
|---------------------------|-------------------------------------------------------------------|
| `psql` not found          | Add `C:\Program Files\PostgreSQL\16\bin` to Windows PATH          |
| Password prompt fails     | Add `-W` flag: `psql -U equipo5proyfin -d asilo_db -W -f DDL.sql` |
| `psycopg2` install fails  | Make sure you're using `psycopg2-binary`, not `psycopg2`          |
| SEED.sql errors on re-run | Data already exists — safe to ignore duplicate key errors         |
