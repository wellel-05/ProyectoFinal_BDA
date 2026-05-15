"""
Pobla MongoDB con datos de demostración alineados con los datos de SEED.sql.
Ejecutar una sola vez: python scripts/seed_mongodb.py
"""
import os, sys, random
from datetime import datetime, timedelta
from dotenv import load_dotenv

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
load_dotenv()

from pymongo import MongoClient, ASCENDING

uri     = os.environ.get('MONGO_URI', 'mongodb://localhost:27017/')
db_name = os.environ.get('MONGO_DB', 'eldercare_nosql')

client = MongoClient(uri)
db     = client[db_name]

# ── Limpia colecciones antes de re-poblar ─────────────────────────────────────
for col in ('eventos_iot', 'checkins_animo', 'logs_aplicacion'):
    db[col].drop()
    print(f'Colección {col} reiniciada.')

# ── Helpers ───────────────────────────────────────────────────────────────────
def ts(days_ago=0, hours_ago=0):
    return datetime.utcnow() - timedelta(days=days_ago, hours=hours_ago)

# IDs según SEED.sql
STAFF_IDS       = [1, 2, 3, 4, 5, 6]
RESIDENTE_IDS   = [1, 2, 3, 4]
BEACON_IDS      = [1, 2, 3, 4]
LECTOR_IDS      = [1, 2, 3]
NFC_TAGS        = ['NFC-MED-001', 'NFC-MED-002', 'NFC-MED-003', 'NFC-MED-004']

# ── eventos_iot ───────────────────────────────────────────────────────────────
iot_docs = []

# Beacons: 60 eventos en los últimos 7 días
for i in range(60):
    iot_docs.append({
        'tipo':            'beacon',
        'timestamp':       ts(days_ago=random.randint(0, 7), hours_ago=random.randint(0, 23)),
        'id_beacon':       random.choice(BEACON_IDS),
        'id_staff':        random.choice(STAFF_IDS),
        'pg_deteccion_id': i + 1,
        'rssi':            random.randint(-90, -50),
    })

# RFID: 30 accesos en los últimos 7 días
for i in range(30):
    autorizado = random.random() > 0.15
    iot_docs.append({
        'tipo':       'rfid',
        'timestamp':  ts(days_ago=random.randint(0, 7), hours_ago=random.randint(0, 23)),
        'id_lector':  random.choice(LECTOR_IDS),
        'id_staff':   random.choice(STAFF_IDS),
        'autorizado': autorizado,
        'registrado_por': 1,
    })

# NFC medicamento: 40 escaneos en los últimos 7 días
for i in range(40):
    exitoso = random.random() > 0.1
    iot_docs.append({
        'tipo':       'nfc_medicamento',
        'timestamp':  ts(days_ago=random.randint(0, 7), hours_ago=random.randint(0, 23)),
        'id_staff':   random.choice([4, 5, 6]),
        'codigo_tag': random.choice(NFC_TAGS),
        'exitoso':    exitoso,
    })

db['eventos_iot'].insert_many(iot_docs)
db['eventos_iot'].create_index([('timestamp', ASCENDING)])
db['eventos_iot'].create_index([('tipo', ASCENDING)])
print(f'eventos_iot: {len(iot_docs)} documentos insertados.')

# ── checkins_animo ────────────────────────────────────────────────────────────
animo_docs = []
for residente_id in RESIDENTE_IDS:
    for day in range(30):
        puntaje = random.choices([1, 2, 3, 4, 5], weights=[5, 10, 30, 35, 20])[0]
        animo_docs.append({
            'timestamp':    ts(days_ago=day),
            'id_residente': residente_id,
            'id_staff':     random.choice([4, 5, 6]),
            'puntaje':      puntaje,
            'notas':        'Generado por seed' if random.random() > 0.7 else None,
            'alerta_baja':  puntaje <= 2,
        })

db['checkins_animo'].insert_many(animo_docs)
db['checkins_animo'].create_index([('timestamp', ASCENDING)])
db['checkins_animo'].create_index([('id_residente', ASCENDING)])
print(f'checkins_animo: {len(animo_docs)} documentos insertados.')

# ── logs_aplicacion ───────────────────────────────────────────────────────────
usernames = ['admin_sistema', 'dra.garcia', 'dr.lopez', 'cuidador1', 'cuidador2', 'cuidador3']
log_docs  = []

for i in range(50):
    exitoso  = random.random() > 0.2
    username = random.choice(usernames)
    log_docs.append({
        'evento':      'login_exitoso' if exitoso else 'login_fallido',
        'timestamp':   ts(days_ago=random.randint(0, 14), hours_ago=random.randint(0, 23)),
        'user_id':     STAFF_IDS[usernames.index(username)] if exitoso else None,
        'username':    username,
        'nivel_acceso': 1 if 'admin' in username else (2 if 'dr' in username else 3),
        'ip':          f'192.168.1.{random.randint(10, 50)}',
        'user_agent':  'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    })

db['logs_aplicacion'].insert_many(log_docs)
db['logs_aplicacion'].create_index([('timestamp', ASCENDING)])
db['logs_aplicacion'].create_index([('evento', ASCENDING)])
print(f'logs_aplicacion: {len(log_docs)} documentos insertados.')

print('\nSeed MongoDB completado.')
client.close()
