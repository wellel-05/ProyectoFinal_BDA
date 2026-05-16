"""
Migracion de contraseñas: texto plano → werkzeug scrypt
Ejecutar UNA SOLA VEZ sobre la base de datos existente.

Uso:
    cd proyectoFinalBDA-main
    python scripts/migrate_passwords.py
"""

import os
from dotenv import load_dotenv
load_dotenv()

import psycopg
from werkzeug.security import generate_password_hash

# Credenciales de los usuarios semilla (texto plano original)
SEED_CREDENTIALS = {
    'admin':    'admin123',
    'jramirez': 'terapeuta123',
    'ltorres':  'terapeuta123',
    'mlopez':   'cuidador123',
    'psanchez': 'cuidador123',
    'agarcia':  'cuidador123',
}

def main():
    conn = psycopg.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        dbname=os.environ.get('DB_NAME', 'asilo_db'),
        user=os.environ.get('DB_USER'),
        password=os.environ.get('DB_PASSWORD'),
        port=int(os.environ.get('DB_PORT', 5432)),
    )
    cur = conn.cursor()

    print("Verificando usuarios en la BD...")
    cur.execute("SELECT username, password_hash FROM usuario_sistema ORDER BY username")
    rows = cur.fetchall()

    needs_update = []
    for username, stored_hash in rows:
        # Si el hash NO empieza con 'scrypt:' o 'pbkdf2:', es texto plano
        if not stored_hash.startswith(('scrypt:', 'pbkdf2:')):
            needs_update.append(username)
            print(f"  [{username}] — texto plano detectado, se actualizara")
        else:
            print(f"  [{username}] — ya tiene hash, se omite")

    if not needs_update:
        print("\nTodos los usuarios ya tienen contraseñas hasheadas. Nada que hacer.")
        conn.close()
        return

    print(f"\nActualizando {len(needs_update)} usuario(s)...")
    for username in needs_update:
        plain = SEED_CREDENTIALS.get(username)
        if not plain:
            print(f"  [AVISO] {username} no esta en SEED_CREDENTIALS — omitido.")
            continue

        new_hash = generate_password_hash(plain)
        cur.execute(
            "UPDATE usuario_sistema SET password_hash = %s WHERE username = %s",
            (new_hash, username)
        )
        print(f"  [{username}] actualizado con hash scrypt")

    conn.commit()
    cur.close()
    conn.close()
    print("\nMigracion completada. Ya puedes iniciar sesion con las credenciales normales.")

if __name__ == '__main__':
    main()
