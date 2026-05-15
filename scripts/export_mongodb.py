"""
Exporta las colecciones de MongoDB a archivos JSON en mongo_exports/.
Ejecutar: python scripts/export_mongodb.py
"""
import os, sys, json
from datetime import datetime
from dotenv import load_dotenv

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
load_dotenv()

from pymongo import MongoClient

uri     = os.environ.get('MONGO_URI', 'mongodb://localhost:27017/')
db_name = os.environ.get('MONGO_DB', 'eldercare_nosql')

client = MongoClient(uri)
db     = client[db_name]

out_dir = os.path.join(os.path.dirname(__file__), '..', 'mongo_exports')
os.makedirs(out_dir, exist_ok=True)

def default_serializer(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f'Type {type(obj)} not serializable')

colecciones = ['eventos_iot', 'checkins_animo', 'logs_aplicacion']

for nombre in colecciones:
    docs = list(db[nombre].find({}, {'_id': 0}))
    path = os.path.join(out_dir, f'{nombre}.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(docs, f, ensure_ascii=False, indent=2, default=default_serializer)
    print(f'[OK] {nombre}.json  - {len(docs)} documentos  ->  {path}')

print(f'\nExportacion completada: {len(colecciones)} colecciones en mongo_exports/')
client.close()
