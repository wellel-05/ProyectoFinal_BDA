import os
import math
os.environ['PGCLIENTENCODING'] = 'UTF8'

from dotenv import load_dotenv
load_dotenv()

import logging
from logging.handlers import RotatingFileHandler

from flask import (Flask, render_template, request, redirect,
                   url_for, session, flash, jsonify)
from flask_wtf.csrf import CSRFProtect
from functools import wraps
from datetime import date, timedelta
from collections import defaultdict
import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from werkzeug.security import check_password_hash, generate_password_hash
from pymongo import MongoClient, DESCENDING
from pymongo.errors import PyMongoError
from datetime import datetime

# ── App & extensiones ─────────────────────────────────────────────────────────

app = Flask(__name__)
app.secret_key = os.environ['SECRET_KEY']
app.config['WTF_CSRF_ENABLED'] = os.environ.get('WTF_CSRF_ENABLED', 'True') == 'True'

csrf = CSRFProtect(app)

# ── Logging ───────────────────────────────────────────────────────────────────

os.makedirs('logs', exist_ok=True)
_log_fmt = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s: %(message)s')

_fh = RotatingFileHandler('logs/eldercare.log', maxBytes=5 * 1024 * 1024, backupCount=3)
_fh.setFormatter(_log_fmt)

_sh = logging.StreamHandler()
_sh.setFormatter(_log_fmt)

logger = logging.getLogger('eldercare')
logger.setLevel(getattr(logging, os.environ.get('LOG_LEVEL', 'INFO')))
logger.addHandler(_fh)
logger.addHandler(_sh)

# ── Base de datos ─────────────────────────────────────────────────────────────

DB_CONFIG = {
    'host':     os.environ.get('DB_HOST', 'localhost'),
    'dbname':   os.environ.get('DB_NAME', 'asilo_db'),
    'user':     os.environ.get('DB_USER'),
    'password': os.environ.get('DB_PASSWORD'),
    'port':     int(os.environ.get('DB_PORT', 5432)),
    'options':  '-c client_encoding=UTF8',
}

_pool: 'ConnectionPool | None' = None

def _get_pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(min_size=2, max_size=10, kwargs=DB_CONFIG, open=True)
        logger.info('Pool de conexiones inicializado (min=2, max=10)')
    return _pool

def get_db():
    try:
        return _get_pool().getconn()
    except Exception as e:
        logger.critical('Pool de conexiones agotado: %s', e)
        raise

def release_db(conn):
    _get_pool().putconn(conn)

# ── DB helpers ────────────────────────────────────────────────────────────────

def query(sql, params=None, fetchone=False, fetchall=False):
    conn = get_db()
    try:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params or ())
            if fetchone:   result = cur.fetchone()
            elif fetchall: result = cur.fetchall()
            else:          result = None
        conn.commit()
        return result
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        logger.error('query error [%.80s]: %s', sql, e)
        return None
    finally:
        release_db(conn)

def call_proc(sql, params=(), user_id=None):
    """Llama un procedimiento con OUT ok INT, OUT msg TEXT."""
    conn = get_db()
    cur = conn.cursor()
    try:
        if user_id is not None:
            cur.execute("SELECT set_config('app.id_usuario', %s, TRUE)", (str(user_id),))
        cur.execute(sql, params)
        row = cur.fetchone()
        conn.commit()
        return (int(row[0]), str(row[1])) if row else (0, 'Sin respuesta del servidor.')
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        logger.error('call_proc error [%.80s]: %s', sql, e)
        return (0, 'Error interno del servidor.')
    finally:
        cur.close()
        release_db(conn)

def call_refcursor(sql, params=()):
    """Llama un procedimiento que abre un REFCURSOR llamado 'resultado'."""
    conn = get_db()
    try:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params)
            cur.execute("FETCH ALL FROM resultado")
            rows = cur.fetchall()
        conn.commit()
        return rows
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        logger.error('refcursor error [%.80s]: %s', sql, e)
        return []
    finally:
        release_db(conn)

# ── MongoDB (NoSQL) ───────────────────────────────────────────────────────────
#
# Colecciones:
#   eventos_iot    — beacons BLE, NFC medicamentos, accesos RFID
#                    Relación con PG: campos pg_*_id referencian IDs de PG
#   checkins_animo — historial de estado de ánimo (duplicado analítico)
#                    Relación con PG: id_residente / id_staff referencian PG
#   logs_aplicacion — logins, logouts, fallos de autenticación
#                    Relación con PG: user_id referencia usuario_sistema

_mongo_client: 'MongoClient | None' = None

def get_mongo_db():
    global _mongo_client
    if _mongo_client is None:
        uri = os.environ.get('MONGO_URI', 'mongodb://localhost:27017/')
        _mongo_client = MongoClient(uri, serverSelectionTimeoutMS=3000)
        logger.info('Cliente MongoDB inicializado: %s', uri)
    return _mongo_client[os.environ.get('MONGO_DB', 'eldercare_nosql')]

def mongo_insert(collection: str, document: dict):
    """Inserta en MongoDB; no interrumpe el flujo principal si falla."""
    try:
        get_mongo_db()[collection].insert_one(document)
    except PyMongoError as e:
        logger.warning('MongoDB insert fallido [%s]: %s', collection, e)

def mongo_find(collection: str, filtro: dict = None, limit: int = 50,
               sort_field: str = 'timestamp') -> list:
    """Consulta documentos de MongoDB. Retorna lista de dicts (sin _id)."""
    try:
        cursor = (get_mongo_db()[collection]
                  .find(filtro or {}, {'_id': 0})
                  .sort(sort_field, DESCENDING)
                  .limit(limit))
        docs = list(cursor)
        for d in docs:
            if isinstance(d.get('timestamp'), datetime):
                d['timestamp'] = d['timestamp'].isoformat()
        return docs
    except PyMongoError as e:
        logger.error('MongoDB find fallido [%s]: %s', collection, e)
        return []

# ── Decoradores de autenticacion ──────────────────────────────────────────────

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

def rol_required(*niveles):
    """Restringe una ruta a uno o mas valores de nivel_acceso."""
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if 'user_id' not in session:
                return redirect(url_for('login'))
            if session.get('nivel_acceso') not in niveles:
                logger.warning('Acceso no autorizado: user_id=%s path=%s',
                               session.get('user_id'), request.path)
                flash('No tienes permiso para acceder a esa seccion.', 'error')
                return redirect(url_for('index'))
            return f(*args, **kwargs)
        return decorated
    return decorator

def familiar_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'familiar_id' not in session:
            return redirect(url_for('familiar_login'))
        return f(*args, **kwargs)
    return decorated

# ── Validacion de formularios ─────────────────────────────────────────────────

def require_fields(form, *fields):
    """Flashea error y retorna False si algun campo requerido esta vacio."""
    for field in fields:
        if not form.get(field, '').strip():
            flash(f'El campo "{field}" es obligatorio.', 'error')
            return False
    return True

# ── Manejadores de errores HTTP ───────────────────────────────────────────────

@app.errorhandler(404)
def not_found(e):
    return render_template('errors/404.html'), 404

@app.errorhandler(500)
def internal_error(e):
    logger.error('Error interno del servidor: %s', e)
    return render_template('errors/500.html'), 500

@app.errorhandler(403)
def forbidden(e):
    flash('Acceso denegado.', 'error')
    return redirect(url_for('index'))

# ── Sidebar por rol ───────────────────────────────────────────────────────────

SIDEBAR = {
    1: {
        'logo_icon':    'fa-shield-halved',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PANEL ADMINISTRATIVO',
        'nav_items': [
            {'endpoint': 'admin_dashboard',  'icon': 'fa-gauge-high',       'label': 'Dashboard'},
            {'endpoint': 'admin_residentes', 'icon': 'fa-users',            'label': 'Residentes'},
            {'endpoint': 'admin_staff',      'icon': 'fa-user-gear',        'label': 'Personal'},
            {'endpoint': 'admin_iot',        'icon': 'fa-map-location-dot', 'label': 'Monitoreo IoT'},
            {'endpoint': 'admin_rfid',       'icon': 'fa-door-open',        'label': 'Accesos RFID'},
            {'endpoint': 'admin_nfc',        'icon': 'fa-nfc-symbol',       'label': 'Tags NFC'},
            {'endpoint': 'admin_actividades',  'icon': 'fa-calendar-check',  'label': 'Actividades NFC'},
            {'endpoint': 'admin_asistencias',  'icon': 'fa-mobile-screen',   'label': 'Asistencias NFC'},
            {'endpoint': 'admin_medicamentos', 'icon': 'fa-pills',           'label': 'Medicamentos'},
            {'endpoint': 'admin_turnos',       'icon': 'fa-clock-rotate-left','label': 'Turnos'},
            {'endpoint': 'admin_reportes',     'icon': 'fa-chart-bar',       'label': 'Reportes'},
            {'endpoint': 'admin_kpi',         'icon': 'fa-ranking-star',      'label': 'KPI'},
            {'endpoint': 'admin_familiares',  'icon': 'fa-people-roof',      'label': 'Familiares'},
            {'endpoint': 'admin_auditoria',   'icon': 'fa-list-check',       'label': 'Auditoria'},
            {'endpoint': 'admin_gps',         'icon': 'fa-location-dot',     'label': 'GPS Residentes'},
        ],
    },
    2: {
        'logo_icon':    'fa-heart-pulse',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PORTAL TERAPEUTA',
        'nav_items': [
            {'endpoint': 'terapeuta_dashboard',  'icon': 'fa-table-columns',        'label': 'Dashboard'},
            {'endpoint': 'terapeuta_residentes', 'icon': 'fa-users',                'label': 'Mis Residentes'},
            {'endpoint': 'terapeuta_sesiones',   'icon': 'fa-calendar-check',       'label': 'Sesiones'},
            {'endpoint': 'terapeuta_incidentes', 'icon': 'fa-triangle-exclamation', 'label': 'Incidentes'},
        ],
    },
    3: {
        'logo_icon':    'fa-hands-holding-circle',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PORTAL CUIDADOR',
        'nav_items': [
            {'endpoint': 'cuidador_dashboard',    'icon': 'fa-table-columns', 'label': 'Dashboard'},
            {'endpoint': 'cuidador_residentes',   'icon': 'fa-users',         'label': 'Mis Residentes'},
            {'endpoint': 'cuidador_medicamentos', 'icon': 'fa-pills',         'label': 'Medicamentos'},
            {'endpoint': 'cuidador_nfc',              'icon': 'fa-mobile-screen',    'label': 'Escaneo NFC'},
            {'endpoint': 'cuidador_asistencias_nfc', 'icon': 'fa-calendar-check', 'label': 'Asistencias NFC'},
            {'endpoint': 'cuidador_gps',              'icon': 'fa-location-dot',   'label': 'GPS'},
        ],
    },
    4: {
        'logo_icon':    'fa-people-roof',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PORTAL FAMILIAR',
        'nav_items': [
            {'endpoint': 'familiar_dashboard', 'icon': 'fa-house-chimney-medical', 'label': 'Mis Residentes'},
            {'endpoint': 'familiar_gps',       'icon': 'fa-location-dot',         'label': 'Ubicacion'},
        ],
    },
}

@app.context_processor
def inject_globals():
    nivel      = session.get('nivel_acceso', 0)
    full_name  = session.get('user_name', '')
    first_name = full_name.split(' ')[0] if full_name else ''
    today      = date.today()
    return {
        'current_date':     today,
        'current_date_str': today.strftime('%d %b %Y'),
        'sidebar':          SIDEBAR.get(nivel, {}),
        'active':           request.endpoint or '',
        'current_user': {
            'name':   full_name,
            'nombre': first_name,
            'role':   session.get('user_role', ''),
            'nivel':  nivel,
        },
    }

# ── Index / Login / Logout ────────────────────────────────────────────────────

@app.route('/')
def index():
    if 'user_id' in session:
        nivel = session.get('nivel_acceso')
        if nivel == 1: return redirect(url_for('admin_dashboard'))
        if nivel == 2: return redirect(url_for('terapeuta_dashboard'))
        if nivel == 3: return redirect(url_for('cuidador_dashboard'))
    return render_template('index.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    # Solo redirigir si hay sesión de staff activa (nivel 1-3), no de familiar
    nivel_actual = session.get('nivel_acceso', 0)
    if 'user_id' in session and nivel_actual in (1, 2, 3):
        if nivel_actual == 1: return redirect(url_for('admin_dashboard'))
        if nivel_actual == 2: return redirect(url_for('terapeuta_dashboard'))
        return redirect(url_for('cuidador_dashboard'))

    # Limpiar sesión familiar residual (nunca la de staff)
    if request.method == 'GET' and 'familiar_id' in session:
        session.clear()

    error = None
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()

        if not username or not password:
            error = 'Usuario y contraseña son obligatorios.'
            return render_template('login.html', error=error)

        rows = call_refcursor("CALL sp_auth_usuario(%s, 'resultado')", (username,))
        user = rows[0] if rows else None

        if user and check_password_hash(user['password_hash'], password):
            call_proc("CALL sp_actualizar_ultimo_login(%s, NULL, NULL)",
                      (user['id_usuario'],))
            logger.info('Login exitoso: user=%s nivel=%s ip=%s',
                        username, user['nivel_acceso'], request.remote_addr)
            mongo_insert('logs_aplicacion', {
                'evento':      'login_exitoso',
                'timestamp':   datetime.utcnow(),
                'user_id':     user['id_usuario'],
                'username':    username,
                'nivel_acceso': user['nivel_acceso'],
                'ip':          request.remote_addr,
                'user_agent':  request.user_agent.string[:200],
            })

            session['user_id']      = user['id_usuario']
            session['staff_id']     = user['id_staff']
            session['user_name']    = f"{user['nombre']} {user['apellidos']}"
            session['user_role']    = user['especialidad']
            session['nivel_acceso'] = user['nivel_acceso']

            nivel = user['nivel_acceso']
            if nivel == 1: return redirect(url_for('admin_dashboard'))
            if nivel == 2: return redirect(url_for('terapeuta_dashboard'))
            return redirect(url_for('cuidador_dashboard'))

        logger.warning('Intento de login fallido: username=%s ip=%s',
                       username, request.remote_addr)
        mongo_insert('logs_aplicacion', {
            'evento':    'login_fallido',
            'timestamp': datetime.utcnow(),
            'username':  username,
            'ip':        request.remote_addr,
            'user_agent': request.user_agent.string[:200],
        })
        error = 'Usuario o contraseña incorrectos.'

    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    logger.info('Logout: user_id=%s', session.get('user_id'))
    session.clear()
    return redirect(url_for('login'))

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL ADMINISTRADOR
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/admin/dashboard')
@rol_required(1)
def admin_dashboard():
    stats_rows = call_refcursor("CALL sp_dashboard_admin('resultado')")
    stats = stats_rows[0] if stats_rows else {}

    incidentes_recientes = query(
        "SELECT * FROM v_incidentes_recientes LIMIT 5", fetchall=True) or []
    sesiones_hoy         = query(
        "SELECT * FROM v_sesiones_hoy", fetchall=True) or []
    staff_turno          = query(
        "SELECT * FROM v_staff_en_turno_hoy", fetchall=True) or []

    return render_template('admin/dashboard.html',
                           total_residentes=stats.get('total_residentes', 0),
                           total_staff=stats.get('total_staff', 0),
                           incidentes_alta=stats.get('incidentes_alta', 0),
                           medicamentos_pendientes=stats.get('meds_pendientes', 0),
                           incidentes_recientes=incidentes_recientes,
                           sesiones_hoy=sesiones_hoy,
                           staff_turno=staff_turno)

# ── Residentes ────────────────────────────────────────────────────────────────

@app.route('/admin/residentes')
@rol_required(1)
def admin_residentes():
    residentes = query("SELECT * FROM v_residentes_resumen", fetchall=True) or []
    return render_template('admin/residentes.html', residentes=residentes)

@app.route('/admin/residentes/nuevo', methods=['GET', 'POST'])
@rol_required(1)
def admin_residente_nuevo():
    cuidadores = call_refcursor("CALL sp_lista_cuidadores('resultado')")

    if request.method == 'POST':
        f = request.form
        if not require_fields(f, 'nombre', 'apellidos', 'fecha_nacimiento', 'sexo'):
            return render_template('admin/residente_nuevo.html', cuidadores=cuidadores)

        ok, msg = call_proc(
            "CALL sp_registrar_residente(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NULL,NULL)",
            (f['nombre'], f['apellidos'], f['fecha_nacimiento'], f['sexo'],
             f.get('habitacion') or None, f.get('diagnostico') or None,
             f.get('nivel_movilidad', 'Autonomo'),
             f.get('contacto') or None, f.get('tel_contacto') or None,
             f.get('id_cuidador') or None),
            user_id=session.get('user_id'))
        flash(msg, 'exito' if ok else 'error')
        if ok:
            return redirect(url_for('admin_residentes'))

    return render_template('admin/residente_nuevo.html', cuidadores=cuidadores)

@app.route('/admin/residentes/<int:id_residente>')
@rol_required(1)
def admin_residente_detalle(id_residente):
    rows = call_refcursor("CALL sp_detalle_residente(%s, 'resultado')", (id_residente,))
    residente = rows[0] if rows else None
    if not residente:
        flash('Residente no encontrado.', 'error')
        return redirect(url_for('admin_residentes'))

    asignaciones = call_refcursor(
        "CALL sp_asignaciones_residente(%s, 'resultado')", (id_residente,))
    sesiones     = call_refcursor(
        "CALL sp_historial_sesiones_residente(%s, 'resultado')", (id_residente,))
    checkins     = call_refcursor(
        "CALL sp_historial_checkins_residente(%s, 'resultado')", (id_residente,))
    incidentes   = call_refcursor(
        "CALL sp_historial_incidentes_residente(%s, 'resultado')", (id_residente,))
    cuidadores   = call_refcursor("CALL sp_lista_cuidadores('resultado')")

    return render_template('admin/residente_detalle.html',
                           residente=residente,
                           asignaciones=asignaciones,
                           sesiones=sesiones,
                           checkins=checkins,
                           incidentes=incidentes,
                           cuidadores=cuidadores)

@app.route('/admin/residentes/<int:id_residente>/editar', methods=['POST'])
@rol_required(1)
def admin_residente_editar(id_residente):
    f = request.form
    ok, msg = call_proc(
        "CALL sp_actualizar_residente(%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (id_residente, f.get('habitacion') or None, f.get('diagnostico') or None,
         f.get('nivel_movilidad', 'Autonomo'),
         f.get('contacto') or None, f.get('tel_contacto') or None),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_residente_detalle', id_residente=id_residente))

@app.route('/admin/residentes/<int:id_residente>/cambiar-cuidador', methods=['POST'])
@rol_required(1)
def admin_cambiar_cuidador(id_residente):
    id_cuidador = request.form.get('id_cuidador', type=int)
    if not id_cuidador:
        flash('Selecciona un cuidador.', 'error')
        return redirect(url_for('admin_residente_detalle', id_residente=id_residente))
    ok, msg = call_proc(
        "CALL sp_cambiar_cuidador(%s,%s,NULL,NULL)",
        (id_residente, id_cuidador),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_residente_detalle', id_residente=id_residente))

@app.route('/admin/residentes/<int:id_residente>/baja', methods=['POST'])
@rol_required(1)
def admin_residente_baja(id_residente):
    ok, msg = call_proc(
        "CALL sp_dar_baja_residente(%s,NULL,NULL)", (id_residente,),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_residentes'))

# ── Staff ─────────────────────────────────────────────────────────────────────

@app.route('/admin/staff')
@rol_required(1)
def admin_staff():
    staff = call_refcursor("CALL sp_lista_staff('resultado')")
    roles = call_refcursor("CALL sp_lista_roles('resultado')")
    return render_template('admin/staff.html', staff=staff, roles=roles)

@app.route('/admin/staff/nuevo', methods=['POST'])
@rol_required(1)
def admin_staff_nuevo():
    f = request.form
    if not require_fields(f, 'nombre', 'apellidos', 'email', 'username', 'password', 'id_rol'):
        return redirect(url_for('admin_staff'))

    ok, msg = call_proc(
        "CALL sp_registrar_staff(%s,%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (f['nombre'], f['apellidos'], f['especialidad'], f['email'],
         f['id_rol'], f['username'], generate_password_hash(f['password'])),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_staff'))

@app.route('/admin/staff/<int:id_staff>/editar', methods=['POST'])
@rol_required(1)
def admin_staff_editar(id_staff):
    f = request.form
    ok, msg = call_proc(
        "CALL sp_actualizar_staff(%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (id_staff, f['nombre'], f['apellidos'], f['especialidad'],
         f['email'], f['id_rol']),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_staff'))

@app.route('/admin/staff/<int:id_staff>/toggle', methods=['POST'])
@rol_required(1)
def admin_staff_toggle(id_staff):
    ok, msg = call_proc(
        "CALL sp_toggle_staff(%s,NULL,NULL)", (id_staff,),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_staff'))

# ── IoT: GPS + Beacon ─────────────────────────────────────────────────────────

@app.route('/admin/iot')
@rol_required(1)
def admin_iot():
    gps_status      = query("SELECT * FROM v_estado_gps_residentes",  fetchall=True) or []
    staff_ubicacion = query("SELECT * FROM v_ubicacion_actual_staff",  fetchall=True) or []
    limite_rows     = call_refcursor("CALL sp_limite_jardin('resultado')")
    limite          = limite_rows[0] if limite_rows else None
    fuera_limite    = [r for r in gps_status if not r['dentro_limite']]

    return render_template('admin/iot.html',
                           gps_status=gps_status,
                           staff_ubicacion=staff_ubicacion,
                           limite=limite,
                           fuera_limite=fuera_limite)

# ── RFID: Accesos ─────────────────────────────────────────────────────────────

@app.route('/admin/rfid')
@rol_required(1)
def admin_rfid():
    accesos_hoy    = query("SELECT * FROM v_accesos_rfid_hoy", fetchall=True) or []
    no_autorizados = call_refcursor(
        "CALL sp_accesos_no_autorizados(%s, 'resultado')", (date.today(),))
    lectores   = call_refcursor("CALL sp_lectores_rfid('resultado')")
    staff_list = call_refcursor("CALL sp_lista_staff_activo('resultado')")

    return render_template('admin/rfid.html',
                           accesos_hoy=accesos_hoy,
                           no_autorizados=no_autorizados,
                           lectores=lectores,
                           staff_list=staff_list)

@app.route('/admin/rfid/registrar', methods=['POST'])
@rol_required(1)
def admin_rfid_registrar():
    f = request.form
    if not require_fields(f, 'id_lector', 'id_staff'):
        return redirect(url_for('admin_rfid'))

    ok, msg = call_proc(
        "CALL sp_registrar_acceso_rfid(%s,%s,NULL,NULL,NULL)",
        (f['id_lector'], f['id_staff']),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')

    mongo_insert('eventos_iot', {
        'tipo':       'rfid',
        'timestamp':  datetime.utcnow(),
        'id_lector':  int(f['id_lector']),
        'id_staff':   int(f['id_staff']),
        'autorizado': bool(ok),
        'registrado_por': session.get('user_id'),
    })
    return redirect(url_for('admin_rfid'))

# ── Medicamentos ──────────────────────────────────────────────────────────────

@app.route('/admin/medicamentos')
@rol_required(1)
def admin_medicamentos():
    tab          = request.args.get('tab', 'horarios')
    horarios     = call_refcursor("CALL sp_lista_horarios_medicamento('resultado')")
    residentes   = call_refcursor("CALL sp_lista_residentes_activos('resultado')")
    medicamentos = call_refcursor("CALL sp_lista_medicamentos('resultado')")
    return render_template('admin/medicamentos.html',
                           tab=tab,
                           horarios=horarios,
                           residentes=residentes,
                           medicamentos=medicamentos)


@app.route('/admin/medicamentos/catalogo/nuevo', methods=['POST'])
@rol_required(1)
def admin_medicamento_catalogo_nuevo():
    f = request.form
    ok, msg = call_proc("CALL sp_registrar_medicamento(%s, %s, %s, NULL, NULL, NULL)",
                        (f['nombre'], f.get('descripcion', ''), f['unidad']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_medicamentos', tab='catalogo'))


@app.route('/admin/medicamentos/catalogo/<int:id_med>/editar', methods=['POST'])
@rol_required(1)
def admin_medicamento_catalogo_editar(id_med):
    f = request.form
    ok, msg = call_proc("CALL sp_actualizar_medicamento(%s, %s, %s, %s, NULL, NULL)",
                        (id_med, f['nombre'], f.get('descripcion', ''), f['unidad']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_medicamentos', tab='catalogo'))


@app.route('/admin/medicamentos/catalogo/<int:id_med>/eliminar', methods=['POST'])
@rol_required(1)
def admin_medicamento_catalogo_eliminar(id_med):
    ok, msg = call_proc("CALL sp_eliminar_medicamento(%s, NULL, NULL)", (id_med,))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_medicamentos', tab='catalogo'))


@app.route('/admin/medicamentos/nuevo', methods=['POST'])
@rol_required(1)
def admin_medicamento_nuevo():
    f = request.form
    ok, msg = call_proc("CALL sp_registrar_horario_medicamento(%s, %s, %s, %s, %s, NULL, NULL, NULL)",
                        (int(f['id_residente']), int(f['id_medicamento']),
                         f['hora_programada'], f['dosis'], f['frecuencia']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_medicamentos'))


@app.route('/admin/medicamentos/toggle/<int:id_horario>', methods=['POST'])
@rol_required(1)
def admin_medicamento_toggle(id_horario):
    ok, msg = call_proc("CALL sp_toggle_horario_medicamento(%s, NULL, NULL, NULL)", (id_horario,))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_medicamentos'))


# ── Turnos ────────────────────────────────────────────────────────────────────

@app.route('/admin/turnos')
@rol_required(1)
def admin_turnos():
    turnos = call_refcursor("CALL sp_lista_turnos('resultado')")
    staff  = call_refcursor("CALL sp_lista_staff_activo('resultado')")
    alas   = call_refcursor("CALL sp_lista_alas('resultado')")
    return render_template('admin/turnos.html', turnos=turnos, staff=staff, alas=alas,
                           today_iso=date.today().isoformat())


@app.route('/admin/turnos/nuevo', methods=['POST'])
@rol_required(1)
def admin_turno_nuevo():
    f = request.form
    ok, msg = call_proc("CALL sp_registrar_turno(%s, %s, %s, %s, %s, NULL, NULL, NULL)",
                        (int(f['id_staff']), int(f['id_ala']),
                         f['fecha'], f['hora_inicio'], f['hora_fin']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_turnos'))


@app.route('/admin/turnos/<int:id_turno>/eliminar', methods=['POST'])
@rol_required(1)
def admin_turno_eliminar(id_turno):
    ok, msg = call_proc("CALL sp_eliminar_turno(%s, NULL, NULL)", (id_turno,))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_turnos'))


# ── Reportes ──────────────────────────────────────────────────────────────────

@app.route('/admin/reportes')
@rol_required(1)
def admin_reportes():
    dias = int(request.args.get('dias', 30))
    semana_inicio = request.args.get(
        'semana', (date.today() - timedelta(days=date.today().weekday())).isoformat())
    selected_cuidador = request.args.get('id_cuidador', '')
    tab = request.args.get('tab', 'cuidadores')

    resumen_todos = call_refcursor(
        "CALL sp_resumen_semanal_cuidador(%s, 'resultado')", (semana_inicio,))
    resumen = ([r for r in resumen_todos if str(r.get('id_staff', '')) == selected_cuidador]
               if selected_cuidador else resumen_todos)
    cuidadores = call_refcursor("CALL sp_lista_cuidadores('resultado')")

    animo_rows   = call_refcursor("CALL sp_evolucion_animo_global(%s, 'resultado')", (dias,))
    animo_labels = [str(r['fecha']) for r in animo_rows]
    animo_data   = [float(r['puntaje_promedio']) for r in animo_rows]
    animo_counts = [int(r['num_registros'])       for r in animo_rows]

    inc_rows = call_refcursor("CALL sp_incidentes_por_severidad(%s, 'resultado')", (dias,))
    inc_map  = defaultdict(lambda: {'Alta': 0, 'Media': 0, 'Baja': 0})
    for r in inc_rows:
        inc_map[r['tipo']][r['severidad']] = int(r['total'])
    tipos     = sorted(inc_map.keys())
    inc_alta  = [inc_map[t]['Alta']  for t in tipos]
    inc_media = [inc_map[t]['Media'] for t in tipos]
    inc_baja  = [inc_map[t]['Baja']  for t in tipos]

    adh_rows        = call_refcursor("CALL sp_adherencia_terapeutica(%s, 'resultado')", (dias,))
    adh_labels      = [r['terapeuta']              for r in adh_rows]
    adh_programadas = [int(r['total_programadas']) for r in adh_rows]
    adh_realizadas  = [int(r['realizadas'])        for r in adh_rows]

    iot_rows   = call_refcursor("CALL sp_resumen_iot(%s, 'resultado')", (dias,))
    iot_labels = [r['tipo_evento'] for r in iot_rows]
    iot_data   = [int(r['total'])  for r in iot_rows]

    car_rows       = call_refcursor("CALL sp_carga_operativa(%s, 'resultado')", (dias,))
    car_labels     = [r['profesional']     for r in car_rows]
    car_roles      = [r['rol']             for r in car_rows]
    car_sesiones   = [int(r['sesiones'])   for r in car_rows]
    car_checkins   = [int(r['checkins'])   for r in car_rows]
    car_incidentes = [int(r['incidentes']) for r in car_rows]

    return render_template('admin/reportes.html',
        tab=tab, dias=dias,
        semana_inicio=semana_inicio, selected_cuidador=selected_cuidador,
        resumen=resumen, cuidadores=cuidadores,
        animo_labels=animo_labels, animo_data=animo_data, animo_counts=animo_counts,
        tipos=tipos, inc_alta=inc_alta, inc_media=inc_media, inc_baja=inc_baja,
        adh_labels=adh_labels, adh_programadas=adh_programadas, adh_realizadas=adh_realizadas,
        iot_labels=iot_labels, iot_data=iot_data,
        car_labels=car_labels, car_roles=car_roles,
        car_sesiones=car_sesiones, car_checkins=car_checkins, car_incidentes=car_incidentes)

# ── Auditoria ─────────────────────────────────────────────────────────────────

@app.route('/admin/auditoria')
@rol_required(1)
def admin_auditoria():
    logs = call_refcursor("CALL sp_log_auditoria('resultado')")
    return render_template('admin/auditoria.html', logs=logs)

# ── KPI — Indicadores Clave de Desempeño ──────────────────────────────────────
# Todas las consultas usan VISTAS como fuente (requisito del rubric).

@app.route('/admin/kpi')
@rol_required(1)
def admin_kpi():
    def pct(num, den):
        try:
            n, d = float(num or 0), float(den or 0)
            return round(n / d * 100, 1) if d else None
        except Exception:
            return None

    def safe_float(val, dec=1):
        try: return round(float(val), dec) if val is not None else None
        except Exception: return None

    def safe_int(val):
        try: return int(val or 0)
        except Exception: return 0

    # ── Fuente: v_residentes_resumen ─────────────────────────────────────────
    res_row = query("""
        SELECT COUNT(*)                                                    AS activos,
               ROUND(AVG(ultimo_puntaje_animo)::NUMERIC, 2)               AS animo_prom,
               SUM(CASE WHEN ultimo_puntaje_animo <= 2 THEN 1 ELSE 0 END) AS animo_critico
        FROM v_residentes_resumen
    """, fetchone=True) or {}
    res_hist = query("SELECT COUNT(*) AS total FROM residente", fetchone=True) or {}

    activos       = safe_int(res_row.get('activos'))
    total_hist    = safe_int(res_hist.get('total')) or activos
    animo_prom    = safe_float(res_row.get('animo_prom'), 2)
    animo_critico = safe_int(res_row.get('animo_critico'))

    # ── Fuente: v_medicamentos_pendientes_hoy ────────────────────────────────
    meds_row  = query("SELECT COUNT(*) AS pendientes FROM v_medicamentos_pendientes_hoy", fetchone=True) or {}
    meds_pend = safe_int(meds_row.get('pendientes'))

    # ── Fuente: v_sesiones_hoy ───────────────────────────────────────────────
    ses_row  = query("""
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN asistio THEN 1 ELSE 0 END) AS asistidas
        FROM v_sesiones_hoy
    """, fetchone=True) or {}
    ses_total  = safe_int(ses_row.get('total'))
    ses_asist  = safe_int(ses_row.get('asistidas'))
    tasa_asist = pct(ses_asist, ses_total)

    # ── Fuente: v_staff_en_turno_hoy ─────────────────────────────────────────
    staff_row = query("SELECT COUNT(*) AS en_turno FROM v_staff_en_turno_hoy", fetchone=True) or {}
    en_turno  = safe_int(staff_row.get('en_turno'))

    # ── Fuente: v_accesos_rfid_hoy ───────────────────────────────────────────
    rfid_row   = query("""
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN acceso_concedido THEN 1 ELSE 0 END) AS autorizados
        FROM v_accesos_rfid_hoy
    """, fetchone=True) or {}
    rfid_total = safe_int(rfid_row.get('total'))
    rfid_auth  = safe_int(rfid_row.get('autorizados'))
    tasa_rfid  = pct(rfid_auth, rfid_total)

    # ── Fuente: v_incidentes_recientes ───────────────────────────────────────
    inc_row    = query("""
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN severidad = 'Alta' THEN 1 ELSE 0 END) AS alta
        FROM v_incidentes_recientes
    """, fetchone=True) or {}
    inc_total    = safe_int(inc_row.get('total'))
    inc_alta_n   = safe_int(inc_row.get('alta'))
    tasa_inc_alt = pct(inc_alta_n, inc_total)

    # ── Fuente: v_estado_gps_residentes ─────────────────────────────────────
    gps_row   = query("""
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN dentro_limite     THEN 1 ELSE 0 END) AS dentro,
               SUM(CASE WHEN NOT dentro_limite THEN 1 ELSE 0 END) AS fuera
        FROM v_estado_gps_residentes
    """, fetchone=True) or {}
    gps_total  = safe_int(gps_row.get('total'))
    gps_fuera  = safe_int(gps_row.get('fuera'))
    tasa_gps   = pct(safe_int(gps_row.get('dentro')), gps_total)

    # ── Fuente: v_adherencia_medicamentos ────────────────────────────────────
    adh_row      = query("""
        SELECT ROUND(AVG(pct_adherencia)::NUMERIC, 1) AS promedio,
               COUNT(CASE WHEN pct_adherencia < 50 THEN 1 END) AS criticos
        FROM v_adherencia_medicamentos
    """, fetchone=True) or {}
    adh_prom     = safe_float(adh_row.get('promedio'))
    adh_criticos = safe_int(adh_row.get('criticos'))

    # ── Fuente: v_resumen_incidentes_mes ─────────────────────────────────────
    t_act = safe_int((query("""
        SELECT COALESCE(SUM(total),0) AS t
        FROM v_resumen_incidentes_mes
        WHERE mes = TO_CHAR(CURRENT_DATE,'YYYY-MM')
    """, fetchone=True) or {}).get('t'))
    t_ant = safe_int((query("""
        SELECT COALESCE(SUM(total),0) AS t
        FROM v_resumen_incidentes_mes
        WHERE mes = TO_CHAR(CURRENT_DATE - INTERVAL '1 month','YYYY-MM')
    """, fetchone=True) or {}).get('t'))
    var_inc = round((t_act - t_ant) / t_ant * 100, 1) if t_ant > 0 else None

    # ── Lista de 15 KPIs ─────────────────────────────────────────────────────
    kpis = [
        {
            'id': 1, 'categoria': 'Operativo', 'icono': 'fa-bed',
            'nombre': 'Tasa de Ocupacion',
            'descripcion': 'Porcentaje de residentes activos sobre el total historico registrado en el sistema.',
            'formula': 'COUNT(activo=TRUE) / COUNT(total_historico) x 100',
            'fuente': 'v_residentes_resumen',
            'valor': pct(activos, total_hist), 'unidad': '%', 'meta': 90, 'meta_dir': 'arriba',
            'interpretacion': '>90% es optimo. <70% indica subutilizacion de la capacidad instalada.',
        },
        {
            'id': 2, 'categoria': 'Clinico', 'icono': 'fa-face-smile',
            'nombre': 'Puntaje Promedio de Estado de Animo',
            'descripcion': 'Promedio del ultimo puntaje de animo registrado para todos los residentes activos.',
            'formula': 'AVG(ultimo_puntaje_animo) de v_residentes_resumen',
            'fuente': 'v_residentes_resumen',
            'valor': animo_prom, 'unidad': '/ 5', 'meta': 3.5, 'meta_dir': 'arriba',
            'interpretacion': '>=4 indica bienestar general. <2 activa protocolos de intervencion inmediata.',
        },
        {
            'id': 3, 'categoria': 'Clinico', 'icono': 'fa-face-frown',
            'nombre': 'Residentes con Animo Critico',
            'descripcion': 'Numero de residentes con ultimo check-in de animo <= 2 (muy bajo o bajo).',
            'formula': 'COUNT(ultimo_puntaje_animo <= 2)',
            'fuente': 'v_residentes_resumen',
            'valor': animo_critico, 'unidad': 'residentes', 'meta': 0, 'meta_dir': 'abajo',
            'interpretacion': 'Cualquier valor >0 genera incidentes automaticos. Meta ideal: 0.',
        },
        {
            'id': 4, 'categoria': 'Clinico', 'icono': 'fa-pills',
            'nombre': 'Dosis de Medicamentos Pendientes Hoy',
            'descripcion': 'Total de dosis programadas para hoy que no han sido administradas ni registradas.',
            'formula': 'COUNT(*) de v_medicamentos_pendientes_hoy',
            'fuente': 'v_medicamentos_pendientes_hoy',
            'valor': meds_pend, 'unidad': 'dosis', 'meta': 0, 'meta_dir': 'abajo',
            'interpretacion': 'Meta: 0 al cierre del turno. Valores altos indican riesgo farmacologico para los pacientes.',
        },
        {
            'id': 5, 'categoria': 'Terapeutico', 'icono': 'fa-calendar-check',
            'nombre': 'Tasa de Asistencia a Sesiones de Terapia',
            'descripcion': 'Porcentaje de sesiones programadas hoy marcadas como asistidas.',
            'formula': 'SUM(asistio=TRUE) / COUNT(*) x 100',
            'fuente': 'v_sesiones_hoy',
            'valor': tasa_asist, 'unidad': '%', 'meta': 80, 'meta_dir': 'arriba',
            'interpretacion': '>=80% indica adherencia terapeutica adecuada. <50% requiere revision del plan de sesiones.',
        },
        {
            'id': 6, 'categoria': 'Terapeutico', 'icono': 'fa-calendar',
            'nombre': 'Sesiones de Terapia Programadas Hoy',
            'descripcion': 'Conteo total de sesiones agendadas para el dia actual en todas las salas.',
            'formula': 'COUNT(*) de v_sesiones_hoy',
            'fuente': 'v_sesiones_hoy',
            'valor': ses_total, 'unidad': 'sesiones', 'meta': None, 'meta_dir': None,
            'interpretacion': 'Indicador de actividad terapeutica diaria para planificar distribucion de recursos.',
        },
        {
            'id': 7, 'categoria': 'Operativo', 'icono': 'fa-user-clock',
            'nombre': 'Personal en Turno Activo Hoy',
            'descripcion': 'Numero de miembros del personal con turno registrado y activo para hoy.',
            'formula': 'COUNT(DISTINCT id_staff) de v_staff_en_turno_hoy',
            'fuente': 'v_staff_en_turno_hoy',
            'valor': en_turno, 'unidad': 'personas', 'meta': None, 'meta_dir': None,
            'interpretacion': '<3 personas por turno puede comprometer la atencion minima requerida.',
        },
        {
            'id': 8, 'categoria': 'Seguridad', 'icono': 'fa-door-open',
            'nombre': 'Tasa de Accesos RFID Autorizados',
            'descripcion': 'Porcentaje de intentos de acceso RFID concedidos sobre el total del dia.',
            'formula': 'SUM(acceso_concedido=TRUE) / COUNT(*) x 100',
            'fuente': 'v_accesos_rfid_hoy',
            'valor': tasa_rfid, 'unidad': '%', 'meta': 95, 'meta_dir': 'arriba',
            'interpretacion': '<95% puede indicar intentos no autorizados. Revisar los accesos denegados inmediatamente.',
        },
        {
            'id': 9, 'categoria': 'Seguridad', 'icono': 'fa-triangle-exclamation',
            'nombre': 'Incidentes de Alta Severidad (7 dias)',
            'descripcion': 'Conteo de incidentes clasificados como Alta severidad en los ultimos 7 dias.',
            'formula': "COUNT(severidad='Alta') de v_incidentes_recientes",
            'fuente': 'v_incidentes_recientes',
            'valor': inc_alta_n, 'unidad': 'incidentes', 'meta': 0, 'meta_dir': 'abajo',
            'interpretacion': '>3 por semana es alerta sistemica. Cada incidente Alta requiere intervencion inmediata.',
        },
        {
            'id': 10, 'categoria': 'Seguridad', 'icono': 'fa-chart-pie',
            'nombre': 'Tasa de Incidentes Criticos',
            'descripcion': 'Proporcion de incidentes Alta respecto al total de incidentes recientes.',
            'formula': "COUNT(Alta) / COUNT(*) x 100",
            'fuente': 'v_incidentes_recientes',
            'valor': tasa_inc_alt, 'unidad': '%', 'meta': 10, 'meta_dir': 'abajo',
            'interpretacion': '<10% indica que la mayoria de eventos son manejables. >30% sugiere deterioro en la seguridad.',
        },
        {
            'id': 11, 'categoria': 'Seguridad', 'icono': 'fa-map-location-dot',
            'nombre': 'Residentes Fuera del Perimetro GPS',
            'descripcion': 'Numero de residentes cuyo ultimo ping GPS los ubica fuera del limite del jardin.',
            'formula': 'SUM(dentro_limite=FALSE)',
            'fuente': 'v_estado_gps_residentes',
            'valor': gps_fuera, 'unidad': 'residentes', 'meta': 0, 'meta_dir': 'abajo',
            'interpretacion': 'Cualquier valor >0 activa protocolo de busqueda. Trigger genera incidente tipo Deambulacion.',
        },
        {
            'id': 12, 'categoria': 'Seguridad', 'icono': 'fa-satellite',
            'nombre': 'Cobertura GPS del Jardin',
            'descripcion': 'Porcentaje de residentes con ping GPS que se encuentran dentro del perimetro autorizado.',
            'formula': 'SUM(dentro_limite=TRUE) / COUNT(*) x 100',
            'fuente': 'v_estado_gps_residentes',
            'valor': tasa_gps, 'unidad': '%', 'meta': 100, 'meta_dir': 'arriba',
            'interpretacion': '100% es el unico valor aceptable. Cualquier porcentaje menor activa emergencia inmediata.',
        },
        {
            'id': 13, 'categoria': 'Clinico', 'icono': 'fa-syringe',
            'nombre': 'Adherencia Global de Medicamentos',
            'descripcion': 'Promedio del porcentaje de adherencia de todos los residentes activos hoy.',
            'formula': 'AVG(pct_adherencia) de v_adherencia_medicamentos',
            'fuente': 'v_adherencia_medicamentos',
            'valor': adh_prom, 'unidad': '%', 'meta': 90, 'meta_dir': 'arriba',
            'interpretacion': '>=90% es nivel optimo. <70% requiere revision del protocolo de administracion de medicamentos.',
        },
        {
            'id': 14, 'categoria': 'Clinico', 'icono': 'fa-circle-exclamation',
            'nombre': 'Residentes con Adherencia Farmacologica Critica',
            'descripcion': 'Numero de residentes con menos del 50% de sus dosis programadas administradas hoy.',
            'formula': 'COUNT(pct_adherencia < 50)',
            'fuente': 'v_adherencia_medicamentos',
            'valor': adh_criticos, 'unidad': 'residentes', 'meta': 0, 'meta_dir': 'abajo',
            'interpretacion': 'Cualquier valor >0 requiere revision inmediata. Riesgo clinico elevado para los pacientes afectados.',
        },
        {
            'id': 15, 'categoria': 'Operativo', 'icono': 'fa-arrow-trend-up',
            'nombre': 'Variacion Mensual de Incidentes',
            'descripcion': 'Cambio porcentual en el numero total de incidentes respecto al mes anterior.',
            'formula': '(mes_actual - mes_anterior) / mes_anterior x 100',
            'fuente': 'v_resumen_incidentes_mes',
            'valor': var_inc, 'unidad': '%', 'meta': -10, 'meta_dir': 'abajo',
            'interpretacion': 'Valores negativos indican mejora. Un incremento >20% mensual requiere revision del plan de cuidados.',
        },
    ]

    resumen = {
        'Clinico':     sum(1 for k in kpis if k['categoria'] == 'Clinico'),
        'Seguridad':   sum(1 for k in kpis if k['categoria'] == 'Seguridad'),
        'Terapeutico': sum(1 for k in kpis if k['categoria'] == 'Terapeutico'),
        'Operativo':   sum(1 for k in kpis if k['categoria'] == 'Operativo'),
    }

    return render_template('admin/kpi.html', kpis=kpis, resumen=resumen)

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL TERAPEUTA
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/terapeuta/dashboard')
@rol_required(2)
def terapeuta_dashboard():
    id_staff = session['staff_id']

    stats_rows = call_refcursor(
        "CALL sp_dashboard_terapeuta(%s, 'resultado')", (id_staff,))
    stats = stats_rows[0] if stats_rows else {}

    sesiones_hoy = call_refcursor(
        "CALL sp_sesiones_hoy_terapeuta(%s, 'resultado')", (id_staff,))
    incidentes   = query("SELECT * FROM v_incidentes_recientes LIMIT 5", fetchall=True) or []

    return render_template('terapeuta/dashboard.html',
                           total_residentes=stats.get('total_residentes', 0),
                           sesiones_hoy=sesiones_hoy,
                           incidentes_activos=stats.get('incidentes_activos', 0),
                           animo_promedio=stats.get('animo_promedio'),
                           incidentes=incidentes)

@app.route('/terapeuta/residentes')
@rol_required(2)
def terapeuta_residentes():
    id_staff   = session['staff_id']
    residentes = call_refcursor(
        "CALL sp_residentes_asignados_terapeuta(%s, 'resultado')", (id_staff,))
    return render_template('terapeuta/residentes.html', residentes=residentes)

@app.route('/terapeuta/residentes/<int:id_residente>')
@rol_required(2)
def terapeuta_residente_detalle(id_residente):
    rows = call_refcursor("CALL sp_detalle_residente(%s, 'resultado')", (id_residente,))
    residente = rows[0] if rows else None
    if not residente:
        flash('Residente no encontrado.', 'error')
        return redirect(url_for('terapeuta_residentes'))

    sesiones = call_refcursor(
        "CALL sp_sesiones_residente_terapeuta(%s, %s, 'resultado')",
        (id_residente, session['staff_id']))

    evolucion_animo = call_refcursor(
        "CALL sp_evolucion_animo_residente(%s, %s, 'resultado')",
        (id_residente, 30))

    incidentes = call_refcursor(
        "CALL sp_incidentes_residente_lista(%s, 'resultado')", (id_residente,))

    salas = call_refcursor("CALL sp_salas('resultado')")

    return render_template('terapeuta/residente_detalle.html',
                           residente=residente,
                           sesiones=sesiones,
                           evolucion_animo=evolucion_animo,
                           incidentes=incidentes,
                           salas=salas,
                           preselect_residente=str(id_residente))

@app.route('/terapeuta/sesiones')
@rol_required(2)
def terapeuta_sesiones():
    sesiones = call_refcursor(
        "CALL sp_sesiones_terapeuta(%s, 'resultado')", (session['staff_id'],))
    return render_template('terapeuta/sesiones.html', sesiones=sesiones)

@app.route('/terapeuta/sesiones/nueva', methods=['GET', 'POST'])
@rol_required(2)
def terapeuta_sesion_nueva():
    id_staff    = session['staff_id']
    residentes  = call_refcursor("CALL sp_residentes_sesion_nueva(%s, 'resultado')", (id_staff,))
    salas       = call_refcursor("CALL sp_salas('resultado')")
    preselect_residente = request.args.get('id_residente', '')
    conflicto = None

    if request.method == 'POST':
        f = request.form
        if not require_fields(f, 'id_residente', 'id_sala', 'fecha_sesion',
                               'duracion_min', 'tipo_sesion'):
            return render_template('terapeuta/sesion_nueva.html',
                                   residentes=residentes, salas=salas,
                                   conflicto=conflicto,
                                   preselect_residente=preselect_residente)

        ok, msg = call_proc(
            "CALL sp_reservar_sesion(%s,%s,%s,%s,%s,%s,NULL,NULL)",
            (f['id_residente'], id_staff, f['id_sala'],
             f['fecha_sesion'], f['duracion_min'], f['tipo_sesion']))
        if ok:
            flash(msg, 'exito')
            return redirect(url_for('terapeuta_sesiones'))
        else:
            conflicto = msg

    return render_template('terapeuta/sesion_nueva.html',
                           residentes=residentes,
                           salas=salas,
                           conflicto=conflicto,
                           preselect_residente=preselect_residente)

@app.route('/terapeuta/sesiones/<int:id_sesion>/editar', methods=['POST'])
@rol_required(2)
def terapeuta_sesion_editar(id_sesion):
    f = request.form
    asistio = f.get('asistio') in ('on', '1', 'true')
    ok, msg = call_proc(
        "CALL sp_actualizar_sesion(%s,%s,%s,NULL,NULL)",
        (id_sesion, asistio, f.get('notas') or None))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('terapeuta_sesiones'))

@app.route('/terapeuta/sesiones/<int:id_sesion>/eliminar', methods=['POST'])
@rol_required(2)
def terapeuta_sesion_eliminar(id_sesion):
    ok, msg = call_proc(
        "CALL sp_eliminar_sesion(%s,%s,NULL,NULL)",
        (id_sesion, session['staff_id']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('terapeuta_sesiones'))

@app.route('/terapeuta/incidentes')
@rol_required(2)
def terapeuta_incidentes():
    incidentes = call_refcursor("CALL sp_todos_incidentes('resultado')")
    return render_template('terapeuta/incidentes.html', incidentes=incidentes)

@app.route('/terapeuta/incidentes/<int:id_incidente>/editar', methods=['POST'])
@rol_required(2)
def terapeuta_incidente_editar(id_incidente):
    f = request.form
    ok, msg = call_proc(
        "CALL sp_actualizar_incidente(%s,%s,%s,%s,NULL,NULL)",
        (id_incidente, f['tipo'], f.get('descripcion') or None, f['severidad']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('terapeuta_incidentes'))

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL CUIDADOR
# ═════════════════════════════════════════════════════════════════════════════

def _mis_residentes_ids(id_staff):
    rows = call_refcursor(
        "CALL sp_ids_residentes_cuidador(%s, 'resultado')", (id_staff,))
    return [r['id_residente'] for r in rows]

@app.route('/cuidador/dashboard')
@rol_required(3)
def cuidador_dashboard():
    id_staff = session['staff_id']
    ids      = _mis_residentes_ids(id_staff)

    meds_pendientes = call_refcursor(
        "CALL sp_meds_pendientes_cuidador(%s, 'resultado')", (id_staff,))

    stats_rows = call_refcursor(
        "CALL sp_dashboard_cuidador(%s, 'resultado')", (id_staff,))
    stats = stats_rows[0] if stats_rows else {}

    animo_bajo = []
    if ids:
        rows = call_refcursor(
            "CALL sp_animo_bajo_cuidador(%s, 'resultado')", (id_staff,))
        animo_bajo = [a for a in rows if a['puntaje'] <= 2]

    return render_template('cuidador/dashboard.html',
                           total_residentes=len(ids),
                           meds_pendientes=meds_pendientes,
                           checkins_hoy=stats.get('checkins_hoy', 0),
                           incidentes_hoy=stats.get('incidentes_hoy', 0),
                           animo_bajo=animo_bajo)

@app.route('/cuidador/residentes')
@rol_required(3)
def cuidador_residentes():
    id_staff   = session['staff_id']
    residentes = call_refcursor(
        "CALL sp_residentes_cuidador_vista(%s, 'resultado')", (id_staff,))
    return render_template('cuidador/residentes.html', residentes=residentes)

@app.route('/cuidador/medicamentos')
@rol_required(3)
def cuidador_medicamentos():
    id_staff      = session['staff_id']
    pendientes    = call_refcursor(
        "CALL sp_meds_pendientes_cuidador(%s, 'resultado')", (id_staff,))
    administrados = call_refcursor(
        "CALL sp_medicamentos_admin_hoy(%s, 'resultado')", (id_staff,))
    return render_template('cuidador/medicamentos.html',
                           pendientes=pendientes,
                           administrados=administrados)

@app.route('/cuidador/checkin', methods=['GET', 'POST'])
@rol_required(3)
def cuidador_checkin():
    id_staff = session['staff_id']
    if request.method == 'POST':
        f = request.form
        if not require_fields(f, 'id_residente', 'puntaje'):
            return redirect(url_for('cuidador_checkin'))

        puntaje = int(f['puntaje'])
        ok, msg = call_proc(
            "CALL sp_checkin_estado_animo(%s,%s,%s,%s,NULL,NULL)",
            (f['id_residente'], id_staff, puntaje, f.get('notas') or None))
        if ok:
            extra = ' Animo bajo — se genero incidente automatico.' if puntaje <= 2 else ''
            flash(f'Check-in registrado correctamente.{extra}', 'exito')
            mongo_insert('checkins_animo', {
                'timestamp':    datetime.utcnow(),
                'id_residente': int(f['id_residente']),
                'id_staff':     id_staff,
                'puntaje':      puntaje,
                'notas':        f.get('notas') or None,
                'alerta_baja':  puntaje <= 2,
            })
        else:
            flash(msg, 'error')
        return redirect(url_for('cuidador_residentes'))

    residentes = call_refcursor(
        "CALL sp_residentes_cuidador_lista(%s, 'resultado')", (id_staff,))
    return render_template('cuidador/checkin.html', residentes=residentes)

@app.route('/cuidador/incidente', methods=['GET', 'POST'])
@rol_required(3)
def cuidador_incidente():
    id_staff = session['staff_id']
    if request.method == 'POST':
        f = request.form
        if not require_fields(f, 'id_residente', 'tipo_incidente', 'severidad'):
            return redirect(url_for('cuidador_incidente'))

        ok, msg = call_proc(
            "CALL sp_registrar_incidente(%s,%s,%s,%s,%s,NULL,NULL)",
            (f['id_residente'], id_staff,
             f['tipo_incidente'], f.get('descripcion') or None, f['severidad']))
        flash('Incidente reportado correctamente.' if ok else msg,
              'exito' if ok else 'error')
        return redirect(url_for('cuidador_residentes'))

    residentes = call_refcursor(
        "CALL sp_residentes_cuidador_lista(%s, 'resultado')", (id_staff,))
    return render_template('cuidador/incidente.html', residentes=residentes)

# ── NFC: Simulacion de escaneo ────────────────────────────────────────────────

@app.route('/cuidador/nfc', methods=['GET', 'POST'])
@rol_required(3)
def cuidador_nfc():
    id_staff = session['staff_id']
    tags_nfc = call_refcursor("CALL sp_tags_nfc('resultado')")
    resultado = None

    if request.method == 'POST':
        codigo_tag = request.form.get('codigo_tag', '').strip()
        if not codigo_tag:
            flash('Debes seleccionar un tag NFC.', 'error')
        else:
            ok, msg = call_proc(
                "CALL sp_log_medicamento_nfc(%s,%s,NULL,NULL)",
                (codigo_tag, id_staff))
            resultado = {'ok': ok, 'msg': msg}
            flash(msg, 'exito' if ok else 'error')
            mongo_insert('eventos_iot', {
                'tipo':       'nfc_medicamento',
                'timestamp':  datetime.utcnow(),
                'id_staff':   id_staff,
                'codigo_tag': codigo_tag,
                'exitoso':    bool(ok),
            })

    log_nfc = call_refcursor(
        "CALL sp_log_nfc_hoy(%s, 'resultado')", (id_staff,))

    return render_template('cuidador/nfc.html',
                           tags_nfc=tags_nfc,
                           resultado=resultado,
                           log_nfc=log_nfc)


# ── NFC — escaneo desde iPhone ───────────────────────────────────────────────

@app.route('/nfc/<codigo_tag>')
@csrf.exempt
def nfc_scan_tag(codigo_tag):
    tag = query(
        "SELECT * FROM nfc_tag WHERE codigo_tag = %s",
        (codigo_tag,), fetchone=True
    )
    if not tag:
        return render_template('nfc_scan.html', error='Tag no registrado en el sistema.', codigo=codigo_tag)

    residente = query(
        "SELECT * FROM residente WHERE id_residente = %s",
        (tag['id_residente'],), fetchone=True
    )

    meds = query(
        """SELECT m.nombre, hm.dosis, hm.hora_programada,
                  COALESCE(
                      (SELECT TRUE FROM log_medicamento lm
                       WHERE lm.id_horario = hm.id_horario
                         AND lm.fecha_administracion::date = CURRENT_DATE
                       LIMIT 1),
                      FALSE
                  ) AS administrado
           FROM horario_medicamento hm
           JOIN medicamento m ON hm.id_medicamento = m.id_medicamento
           WHERE hm.id_residente = %s AND hm.activo = TRUE
           ORDER BY hm.hora_programada""",
        (tag['id_residente'],), fetchall=True
    ) or []

    eventos = query(
        """SELECT ne.escaneado_en,
                  s.nombre || ' ' || s.apellidos AS staff
           FROM nfc_evento ne
           JOIN staff s ON ne.id_staff = s.id_staff
           WHERE ne.id_tag = %s
           ORDER BY ne.escaneado_en DESC LIMIT 5""",
        (tag['id_tag'],), fetchall=True
    ) or []

    id_staff = session.get('staff_id')
    if id_staff:
        conn = get_db()
        try:
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO nfc_evento (id_tag, id_staff) VALUES (%s, %s)",
                (tag['id_tag'], id_staff)
            )
            conn.commit()
            cur.close()
            logger.info('NFC scan: tag=%s staff=%s residente=%s', codigo_tag, id_staff, tag['id_residente'])
        except Exception as e:
            conn.rollback()
            logger.error('nfc_scan_tag log error: %s', e)
        finally:
            release_db(conn)

    return render_template('nfc_scan.html',
                           tag=tag, residente=residente,
                           meds=meds, eventos=eventos, error=None)


# ── NFC — gestion admin ───────────────────────────────────────────────────────

@app.route('/admin/nfc')
@rol_required(1)
def admin_nfc():
    tags = query(
        """SELECT nt.id_tag, nt.codigo_tag, nt.descripcion,
                  r.nombre || ' ' || r.apellidos AS residente,
                  r.habitacion,
                  (SELECT COUNT(*) FROM nfc_evento ne WHERE ne.id_tag = nt.id_tag) AS total_escaneos,
                  (SELECT ne2.escaneado_en FROM nfc_evento ne2
                   WHERE ne2.id_tag = nt.id_tag
                   ORDER BY ne2.escaneado_en DESC LIMIT 1) AS ultimo_escaneo
           FROM nfc_tag nt
           JOIN residente r ON nt.id_residente = r.id_residente
           ORDER BY r.apellidos""",
        fetchall=True
    ) or []

    residentes = query(
        "SELECT id_residente, nombre || ' ' || apellidos AS nombre, habitacion FROM residente WHERE activo = TRUE ORDER BY apellidos",
        fetchall=True
    ) or []

    host = request.host
    return render_template('admin/nfc.html',
                           tags=tags, residentes=residentes,
                           host=host)


@app.route('/admin/nfc/asignar', methods=['POST'])
@rol_required(1)
def admin_nfc_asignar():
    codigo   = request.form.get('codigo_tag', '').strip().upper()
    id_res   = request.form.get('id_residente', '').strip()
    desc     = request.form.get('descripcion', '').strip()

    if not codigo or not id_res:
        flash('El codigo del tag y el residente son obligatorios.', 'error')
        return redirect(url_for('admin_actividades'))

    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO nfc_tag (codigo_tag, id_residente, descripcion) VALUES (%s, %s, %s)",
            (codigo, int(id_res), desc or None)
        )
        conn.commit()
        cur.close()
        flash(f'Tag {codigo} asignado correctamente.', 'exito')
        logger.info('NFC tag creado: codigo=%s residente=%s', codigo, id_res)
    except Exception as e:
        conn.rollback()
        if 'unique' in str(e).lower():
            flash(f'El codigo {codigo} ya esta registrado.', 'error')
        else:
            flash('Error al registrar el tag.', 'error')
        logger.error('admin_nfc_asignar error: %s', e)
    finally:
        release_db(conn)

    return redirect(url_for('admin_actividades'))


@app.route('/admin/nfc/eliminar/<int:id_tag>', methods=['POST'])
@rol_required(1)
def admin_nfc_eliminar(id_tag):
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM nfc_tag WHERE id_tag = %s", (id_tag,))
        conn.commit()
        cur.close()
        flash('Tag eliminado.', 'exito')
    except Exception as e:
        conn.rollback()
        flash('No se pudo eliminar el tag.', 'error')
        logger.error('admin_nfc_eliminar error: %s', e)
    finally:
        release_db(conn)
    return redirect(url_for('admin_actividades'))


# ── IoT stats (JSON para graficas) ───────────────────────────────────────────

@app.route('/admin/iot/stats')
@rol_required(1)
def admin_iot_stats():
    """JSON con datos de beacon para las graficas Highcharts en tiempo real."""
    por_ala = query("""
        SELECT a.nombre AS ala, COUNT(*) AS total
        FROM deteccion_beacon db
        JOIN beacon b  ON db.id_beacon = b.id_beacon
        JOIN ala    a  ON b.id_ala     = a.id_ala
        WHERE db.detectado_en >= CURRENT_DATE
        GROUP BY a.nombre ORDER BY total DESC
    """, fetchall=True) or []

    por_hora = query("""
        SELECT EXTRACT(HOUR FROM detectado_en)::INT AS hora, COUNT(*) AS total
        FROM deteccion_beacon
        WHERE detectado_en >= CURRENT_DATE
        GROUP BY hora ORDER BY hora
    """, fetchall=True) or []

    staff_activo = query("""
        SELECT a.nombre AS ala, COUNT(DISTINCT latest.id_staff) AS staff
        FROM (
            SELECT DISTINCT ON (id_staff) id_staff, id_beacon
            FROM deteccion_beacon
            WHERE detectado_en >= NOW() - INTERVAL '60 minutes'
            ORDER BY id_staff, detectado_en DESC
        ) latest
        JOIN beacon b ON latest.id_beacon = b.id_beacon
        JOIN ala    a ON b.id_ala = a.id_ala
        GROUP BY a.nombre ORDER BY a.nombre
    """, fetchall=True) or []

    total_hoy = query(
        "SELECT COUNT(*) AS n FROM deteccion_beacon WHERE detectado_en >= CURRENT_DATE",
        fetchone=True
    )

    return jsonify({
        'ok':           True,
        'por_ala':      [dict(r) for r in por_ala],
        'por_hora':     [dict(r) for r in por_hora],
        'staff_activo': [dict(r) for r in staff_activo],
        'total_hoy':    int(total_hoy['n']) if total_hoy else 0,
    })


# ── API IoT ───────────────────────────────────────────────────────────────────

def _check_iot_key():
    """Valida la API key enviada en el header X-API-Key."""
    expected = os.environ.get('IOT_API_KEY', '')
    return request.headers.get('X-API-Key', '') == expected


@app.route('/api/beacons', methods=['GET'])
@csrf.exempt
def api_beacons_list():
    """Lista los beacons configurados en la BD (para que el scanner sepa que ID usar)."""
    if not _check_iot_key():
        return jsonify({'ok': False, 'msg': 'API key invalida'}), 401
    rows = query(
        """SELECT b.id_beacon, b.nombre, a.nombre AS ala
           FROM beacon b JOIN ala a ON b.id_ala = a.id_ala
           ORDER BY b.id_beacon""",
        fetchall=True
    )
    return jsonify({'ok': True, 'beacons': [dict(r) for r in (rows or [])]})


@app.route('/api/beacon', methods=['POST'])
@csrf.exempt
def api_beacon():
    """Registra una deteccion de beacon enviada por el scanner BLE."""
    if not _check_iot_key():
        return jsonify({'ok': False, 'msg': 'API key invalida'}), 401

    data = request.get_json(silent=True)
    if not data:
        return jsonify({'ok': False, 'msg': 'Se esperaba JSON en el body'}), 400

    id_beacon = data.get('id_beacon')
    id_staff  = data.get('id_staff')

    if not id_beacon or not id_staff:
        return jsonify({'ok': False, 'msg': 'id_beacon e id_staff son requeridos'}), 400

    conn = get_db()
    try:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute(
            """INSERT INTO deteccion_beacon (id_beacon, id_staff)
               VALUES (%s, %s)
               RETURNING id_deteccion, detectado_en""",
            (id_beacon, id_staff)
        )
        row = cur.fetchone()
        conn.commit()
        cur.close()
        logger.info('Beacon detectado: beacon=%s staff=%s deteccion=%s', id_beacon, id_staff, row['id_deteccion'])
        mongo_insert('eventos_iot', {
            'tipo':             'beacon',
            'timestamp':        datetime.utcnow(),
            'id_beacon':        id_beacon,
            'id_staff':         id_staff,
            'pg_deteccion_id':  row['id_deteccion'],
            'rssi':             data.get('rssi'),
        })
        return jsonify({
            'ok': True,
            'id_deteccion': row['id_deteccion'],
            'detectado_en': row['detectado_en'].isoformat()
        })
    except Exception as e:
        conn.rollback()
        logger.error('api_beacon error: %s', e)
        return jsonify({'ok': False, 'msg': 'Error al registrar deteccion'}), 500
    finally:
        release_db(conn)


# ═════════════════════════════════════════════════════════════════════════════
# PORTAL FAMILIAR
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/familiar/login', methods=['GET', 'POST'])
def familiar_login():
    if request.method == 'GET':
        session.pop('familiar_id', None)

    error = None
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()

        if not username or not password:
            error = 'Usuario y contrasena son obligatorios.'
        else:
            rows = call_refcursor("CALL sp_auth_familiar(%s, 'resultado')", (username,))
            user = rows[0] if rows else None

            if user and check_password_hash(user['password_hash'], password):
                mongo_insert('logs_aplicacion', {
                    'evento':    'login_exitoso_familiar',
                    'timestamp': datetime.utcnow(),
                    'user_id':   user['id_usuario'],
                    'username':  username,
                    'ip':        request.remote_addr,
                })
                session['familiar_id']  = user['id_familiar']
                session['user_name']    = f"{user['nombre']} {user['apellidos']}"
                session['nivel_acceso'] = 4
                return redirect(url_for('familiar_dashboard'))

            mongo_insert('logs_aplicacion', {
                'evento':    'login_fallido_familiar',
                'timestamp': datetime.utcnow(),
                'username':  username,
                'ip':        request.remote_addr,
            })
            error = 'Usuario o contrasena incorrectos.'

    return render_template('familiar/login.html', error=error)


@app.route('/familiar/logout')
def familiar_logout():
    session.clear()
    return redirect(url_for('familiar_login'))


@app.route('/familiar/dashboard')
@familiar_required
def familiar_dashboard():
    id_familiar = session['familiar_id']
    residentes  = call_refcursor(
        "CALL sp_residentes_del_familiar(%s, 'resultado')", (id_familiar,))
    return render_template('familiar/dashboard.html', residentes=residentes)


@app.route('/familiar/residente/<int:id_residente>')
@familiar_required
def familiar_residente(id_residente):
    id_familiar = session['familiar_id']

    # Verificar que este familiar tenga acceso a este residente
    vinculo = query("""
        SELECT 1 FROM v_familiar_residente_info
        WHERE id_residente = %s AND id_familiar = %s
        LIMIT 1
    """, (id_residente, id_familiar), fetchone=True)

    if not vinculo:
        flash('No tienes acceso a la informacion de este residente.', 'error')
        return redirect(url_for('familiar_dashboard'))

    info_rows = query("""
        SELECT * FROM v_familiar_residente_info
        WHERE id_residente = %s AND id_familiar = %s
        LIMIT 1
    """, (id_residente, id_familiar), fetchone=True)

    sesiones   = query("""
        SELECT * FROM v_familiar_sesiones
        WHERE id_residente = %s LIMIT 10
    """, (id_residente,), fetchall=True) or []

    medicamentos = query("""
        SELECT * FROM v_familiar_medicamentos
        WHERE id_residente = %s ORDER BY hora_programada
    """, (id_residente,), fetchall=True) or []

    incidentes = query("""
        SELECT * FROM v_familiar_incidentes
        WHERE id_residente = %s LIMIT 15
    """, (id_residente,), fetchall=True) or []

    animo_rows = query("""
        SELECT * FROM v_familiar_animo
        WHERE id_residente = %s
    """, (id_residente,), fetchall=True) or []

    animo_labels = [str(r['etiqueta'])  for r in animo_rows]
    animo_data   = [int(r['puntaje'])   for r in animo_rows]

    return render_template('familiar/residente.html',
                           info=info_rows,
                           sesiones=sesiones,
                           medicamentos=medicamentos,
                           incidentes=incidentes,
                           animo_labels=animo_labels,
                           animo_data=animo_data)


# ── Admin: gestión de familiares ──────────────────────────────────────────────

@app.route('/admin/familiares')
@rol_required(1)
def admin_familiares():
    familiares = call_refcursor("CALL sp_lista_familiares('resultado')")
    residentes = query("SELECT id_residente, nombre || ' ' || apellidos AS nombre_completo, habitacion FROM residente WHERE activo = TRUE ORDER BY apellidos", fetchall=True) or []
    return render_template('admin/familiares.html',
                           familiares=familiares, residentes=residentes)


@app.route('/admin/familiares/nuevo', methods=['POST'])
@rol_required(1)
def admin_familiares_nuevo():
    f = request.form
    if not require_fields(f, 'nombre', 'apellidos', 'email', 'parentesco',
                          'id_residente', 'username', 'password'):
        return redirect(url_for('admin_familiares'))

    pwd_hash = generate_password_hash(f['password'])
    ok, msg  = call_proc(
        "CALL sp_registrar_familiar(%s,%s,%s,%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (f['nombre'], f['apellidos'], f['parentesco'], f['email'],
         f.get('telefono') or None, int(f['id_residente']),
         f['username'], pwd_hash,
         f.get('es_principal') == 'on'),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_familiares'))


@app.route('/admin/familiares/<int:id_familiar>/toggle', methods=['POST'])
@rol_required(1)
def admin_familiar_toggle(id_familiar):
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE familiar SET activo = NOT activo WHERE id_familiar = %s", (id_familiar,))
        cur.execute("UPDATE usuario_familiar SET activo = NOT activo WHERE id_familiar = %s", (id_familiar,))
        conn.commit()
        cur.close()
        flash('Estado del familiar actualizado.', 'exito')
    except Exception as e:
        conn.rollback()
        logger.error('toggle familiar error: %s', e)
        flash('Error al actualizar el estado.', 'error')
    finally:
        release_db(conn)
    return redirect(url_for('admin_familiares'))

# ── API MongoDB ───────────────────────────────────────────────────────────────

@app.route('/api/mongo/eventos_iot')
@rol_required(1)
def api_mongo_eventos_iot():
    """Últimos eventos IoT desde MongoDB (beacon, rfid, nfc_medicamento)."""
    limit = min(int(request.args.get('limit', 50)), 200)
    tipo  = request.args.get('tipo')
    filtro = {'tipo': tipo} if tipo else {}
    docs = mongo_find('eventos_iot', filtro, limit)
    return jsonify({'ok': True, 'data': docs, 'total': len(docs)})


@app.route('/api/mongo/animo')
@rol_required(1, 2, 3)
def api_mongo_animo():
    """Historial de check-ins de estado de ánimo desde MongoDB."""
    limit = min(int(request.args.get('limit', 100)), 500)
    id_residente = request.args.get('id_residente')
    filtro = {}
    if id_residente:
        filtro['id_residente'] = int(id_residente)
    docs = mongo_find('checkins_animo', filtro, limit)
    return jsonify({'ok': True, 'data': docs, 'total': len(docs)})


@app.route('/api/mongo/logs')
@rol_required(1)
def api_mongo_logs():
    """Logs de autenticación y sistema desde MongoDB."""
    limit = min(int(request.args.get('limit', 50)), 200)
    evento = request.args.get('evento')
    filtro = {'evento': evento} if evento else {}
    docs = mongo_find('logs_aplicacion', filtro, limit)
    return jsonify({'ok': True, 'data': docs, 'total': len(docs)})


@app.route('/api/mongo/resumen_iot')
@rol_required(1)
def api_mongo_resumen_iot():
    """Conteo de eventos IoT agrupados por tipo desde MongoDB."""
    docs = mongo_find('eventos_iot', {}, limit=500)
    resumen = {}
    for d in docs:
        t = d.get('tipo', 'otro')
        resumen[t] = resumen.get(t, 0) + 1
    return jsonify({'ok': True, 'data': resumen, 'total': len(docs)})


@app.route('/api/mongo/actividad_diaria')
@rol_required(1)
def api_mongo_actividad_diaria():
    """Actividad diaria de los últimos 14 días desde logs_aplicacion."""
    docs = mongo_find('logs_aplicacion', {}, limit=500)
    dias = {}
    for d in docs:
        ts = d.get('timestamp')
        if not ts:
            continue
        if isinstance(ts, str):
            try:
                ts = datetime.fromisoformat(ts)
            except Exception:
                continue
        fecha = ts.strftime('%Y-%m-%d')
        if fecha not in dias:
            dias[fecha] = {'logins': 0, 'fallidos': 0, 'alertas': 0}
        ev = d.get('evento', '')
        if 'login_exitoso' in ev:
            dias[fecha]['logins'] += 1
        elif 'login_fallido' in ev:
            dias[fecha]['fallidos'] += 1
        elif 'alerta' in ev:
            dias[fecha]['alertas'] += 1

    hoy = datetime.utcnow().date()
    resultado = []
    for i in range(13, -1, -1):
        fecha = (hoy - timedelta(days=i)).strftime('%Y-%m-%d')
        entrada = dias.get(fecha, {'logins': 0, 'fallidos': 0, 'alertas': 0})
        resultado.append({'fecha': fecha, **entrada})
    return jsonify({'ok': True, 'data': resultado})


# ═════════════════════════════════════════════════════════════════════════════
# GPS / TRACCAR (OsmAnd HTTP protocol)
# ═════════════════════════════════════════════════════════════════════════════

def haversine_m(lat1, lon1, lat2, lon2):
    """Distancia en metros entre dos coordenadas GPS (fórmula Haversine)."""
    R = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _check_geofences(device_id, lat, lon):
    """Evalúa geocercas tras cada fix GPS; genera alertas cuando corresponde."""
    conn = get_db()
    try:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute("SELECT * FROM zona_gps WHERE activo = TRUE")
        for zona in cur.fetchall():
            dist = haversine_m(lat, lon, float(zona['latitud']), float(zona['longitud']))
            if dist <= zona['radio_m'] and zona['tipo'] == 'peligrosa':
                cur.execute("""
                    SELECT 1 FROM alerta_gps
                    WHERE device_id=%s AND id_zona=%s AND atendida=FALSE
                    AND ts_alerta > NOW() - INTERVAL '30 minutes'
                    LIMIT 1
                """, (device_id, zona['id_zona']))
                if not cur.fetchone():
                    msg = (f"Residente detectado en zona peligrosa "
                           f"'{zona['nombre']}' ({int(dist)} m del centro)")
                    cur.execute("""
                        INSERT INTO alerta_gps
                            (device_id, id_zona, tipo, latitud, longitud, mensaje)
                        VALUES (%s,%s,'entrada_zona_peligrosa',%s,%s,%s)
                    """, (device_id, zona['id_zona'], lat, lon, msg))
                    mongo_insert('logs_aplicacion', {
                        'evento': 'alerta_gps', 'device_id': device_id,
                        'zona': zona['nombre'], 'mensaje': msg,
                        'timestamp': datetime.utcnow(),
                    })
        conn.commit()
        cur.close()
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        logger.error('geofence check error: %s', e)
    finally:
        release_db(conn)


@app.route('/api/gps', methods=['GET', 'POST'])
@csrf.exempt
def api_gps_receiver():
    """Endpoint Traccar Client. Acepta GET/POST en cualquier formato."""
    # Recolectar params de TODAS las fuentes posibles
    raw = {}
    raw.update(request.args.to_dict())          # query string
    raw.update(request.form.to_dict())          # form-data
    try:                                        # JSON body
        j = request.get_json(silent=True, force=True) or {}
        raw.update(j)
    except Exception:
        pass
    try:                                        # raw body (si Content-Type falta)
        from urllib.parse import parse_qs
        body_str = request.get_data(as_text=True)
        if body_str:
            parsed = parse_qs(body_str)
            raw.update({k: v[0] for k, v in parsed.items()})
    except Exception:
        pass

    logger.info('GPS recv [%s] raw=%s', request.method, raw)

    def g(name, cast=None, aliases=()):
        for key in (name,) + aliases:
            val = raw.get(key)
            if val is not None and str(val).strip() != '':
                try:
                    return cast(val) if cast else str(val).strip()
                except Exception:
                    continue
        return None

    device_id = g('id', aliases=('deviceId', 'device_id', 'identifier')) or ''
    lat  = g('lat',  float, ('latitude',))
    lon  = g('lon',  float, ('longitude',))

    if not device_id or lat is None or lon is None:
        logger.warning('GPS recv 400 — faltan campos. raw=%s', raw)
        return '', 400

    # Extraer campos desde nested location.coords si existen
    loc   = raw.get('location', {})
    coords = loc.get('coords', {}) if isinstance(loc, dict) else {}

    def _flt(val):
        try:
            v = float(val)
            return None if v < 0 else v   # -1 = sin dato en iOS
        except Exception:
            return None

    alt      = _flt(coords.get('altitude') or g('altitude', float, ('alt',)))
    speed_ms = _flt(coords.get('speed')    or g('speed',    float))
    bearing  = _flt(coords.get('heading')  or g('bearing',  float, ('course',)))
    accuracy = _flt(coords.get('accuracy') or g('accuracy', float))

    # Batería: iOS envía fraction (0.0-1.0) dentro de location.battery.level
    batt = None
    try:
        b = loc.get('battery', {}) if isinstance(loc, dict) else {}
        batt = int(float(b.get('level', -1)) * 100) if b.get('level', -1) >= 0 else None
    except Exception:
        pass

    ts_raw = g('timestamp')

    speed_kmh = round(speed_ms * 3.6, 1) if speed_ms is not None else None
    ts_dev = None
    if ts_raw:
        try:
            ts_dev = datetime.fromisoformat(ts_raw.replace('Z', '+00:00'))
        except Exception:
            try:
                ts_dev = datetime.fromtimestamp(int(ts_raw))
            except Exception:
                pass

    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO posicion_gps
                (device_id, latitud, longitud, altitud, velocidad_kmh,
                 rumbo, precision_m, bateria, ts_dispositivo)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """, (device_id, lat, lon, alt, speed_kmh, bearing, accuracy, batt, ts_dev))
        conn.commit()
        cur.close()
    except Exception as e:
        conn.rollback()
        logger.error('GPS insert error: %s', e)
        return '', 500
    finally:
        release_db(conn)

    _check_geofences(device_id, lat, lon)
    mongo_insert('eventos_iot', {
        'tipo': 'gps_update', 'device_id': device_id,
        'latitud': lat, 'longitud': lon,
        'timestamp': datetime.utcnow(),
    })
    return '', 200


def _gps_posiciones_filtradas():
    """Devuelve las últimas posiciones filtradas según el rol en sesión."""
    nivel = session.get('nivel_acceso', 0)
    if nivel == 0:
        return []

    rows = query("""
        SELECT DISTINCT ON (d.device_id)
            d.device_id, d.id_residente,
            r.nombre || ' ' || r.apellidos AS residente,
            r.habitacion,
            p.latitud, p.longitud, p.velocidad_kmh, p.bateria, p.rumbo,
            p.ts_servidor,
            EXTRACT(EPOCH FROM (NOW() - p.ts_servidor))::INT AS hace_seg
        FROM dispositivo_gps d
        JOIN residente r       ON d.id_residente = r.id_residente
        JOIN posicion_gps p    USING (device_id)
        WHERE d.activo = TRUE
        ORDER BY d.device_id, p.ts_servidor DESC
    """, fetchall=True) or []

    if nivel == 3:
        sid = session.get('staff_id')
        mis_ids = {r['id_residente'] for r in (query("""
            SELECT id_residente FROM asignacion
            WHERE id_staff=%s AND tipo_rol='Cuidador' AND fecha_fin IS NULL
        """, (sid,), fetchall=True) or [])}
        rows = [r for r in rows if r['id_residente'] in mis_ids]
    elif nivel == 4:
        id_fam = session.get('familiar_id')
        mis_ids = {r['id_residente'] for r in (call_refcursor(
            "CALL sp_residentes_del_familiar(%s,'resultado')", (id_fam,)) or [])}
        rows = [r for r in rows if r['id_residente'] in mis_ids]

    result = []
    for r in rows:
        seg = r['hace_seg'] or 0
        if seg < 60:    hace = 'Ahora mismo'
        elif seg < 3600: hace = f'Hace {seg//60} min'
        else:           hace = f'Hace {seg//3600} h'
        result.append({
            'device_id':    r['device_id'],
            'id_residente': r['id_residente'],
            'residente':    r['residente'],
            'habitacion':   r['habitacion'] or '—',
            'latitud':      float(r['latitud']),
            'longitud':     float(r['longitud']),
            'velocidad_kmh': float(r['velocidad_kmh'] or 0),
            'bateria':      r['bateria'],
            'rumbo':        float(r['rumbo'] or 0),
            'hace':         hace,
        })
    return result


@app.route('/api/gps/posiciones')
def api_gps_posiciones():
    nivel = session.get('nivel_acceso', 0)
    familiar_ok = bool(session.get('familiar_id'))
    if not nivel and not familiar_ok:
        return jsonify([])
    return jsonify(_gps_posiciones_filtradas())


@app.route('/api/gps/zonas')
def api_gps_zonas():
    nivel = session.get('nivel_acceso', 0)
    familiar_ok = bool(session.get('familiar_id'))
    if not nivel and not familiar_ok:
        return jsonify([])
    zonas = query("SELECT * FROM zona_gps WHERE activo=TRUE ORDER BY id_zona", fetchall=True) or []
    return jsonify([{
        'id_zona':  z['id_zona'], 'nombre': z['nombre'],
        'latitud':  float(z['latitud']), 'longitud': float(z['longitud']),
        'radio_m':  z['radio_m'], 'tipo': z['tipo'], 'color': z['color'],
    } for z in zonas])


@app.route('/api/gps/alertas/count')
@rol_required(1)
def api_gps_alertas_count():
    rows = query("SELECT COUNT(*) AS n FROM alerta_gps WHERE atendida=FALSE", fetchone=True)
    return jsonify({'count': int(rows['n']) if rows else 0})


# ── Admin GPS ─────────────────────────────────────────────────────────────────

@app.route('/admin/gps')
@rol_required(1)
def admin_gps():
    dispositivos = query("""
        SELECT d.*, r.nombre||' '||r.apellidos AS residente_nombre
        FROM dispositivo_gps d
        LEFT JOIN residente r ON d.id_residente = r.id_residente
        WHERE d.activo = TRUE ORDER BY d.fecha_alta DESC
    """, fetchall=True) or []
    zonas = query("SELECT * FROM zona_gps WHERE activo=TRUE ORDER BY creado_en DESC", fetchall=True) or []
    alertas = query("""
        SELECT a.*, r.nombre||' '||r.apellidos AS residente_nombre,
               z.nombre AS zona_nombre
        FROM alerta_gps a
        LEFT JOIN dispositivo_gps d ON a.device_id=d.device_id
        LEFT JOIN residente r ON d.id_residente=r.id_residente
        LEFT JOIN zona_gps z ON a.id_zona=z.id_zona
        WHERE a.atendida=FALSE
        ORDER BY a.ts_alerta DESC LIMIT 50
    """, fetchall=True) or []
    residentes = query("""
        SELECT id_residente, nombre||' '||apellidos AS nombre_completo, habitacion
        FROM residente WHERE activo=TRUE ORDER BY nombre
    """, fetchall=True) or []
    return render_template('admin/gps.html',
        dispositivos=dispositivos, zonas=zonas,
        alertas=alertas, residentes=residentes,
        alertas_count=len(alertas))


@app.route('/admin/gps/dispositivo/nuevo', methods=['POST'])
@rol_required(1)
def admin_gps_dispositivo_nuevo():
    device_id    = request.form.get('device_id', '').strip()
    id_residente = request.form.get('id_residente', type=int)
    nombre       = request.form.get('nombre', '').strip()
    if not device_id or not id_residente:
        flash('device_id y residente son obligatorios.', 'error')
        return redirect(url_for('admin_gps'))
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO dispositivo_gps (device_id, id_residente, nombre)
            VALUES (%s,%s,%s)
            ON CONFLICT (device_id) DO UPDATE
                SET id_residente=EXCLUDED.id_residente,
                    nombre=EXCLUDED.nombre, activo=TRUE
        """, (device_id, id_residente, nombre or device_id))
        conn.commit(); cur.close()
        flash('Dispositivo registrado correctamente.', 'exito')
    except Exception as e:
        conn.rollback(); flash('Error al registrar dispositivo.', 'error')
    finally:
        release_db(conn)
    return redirect(url_for('admin_gps'))


@app.route('/admin/gps/dispositivo/<int:id_disp>/delete', methods=['POST'])
@rol_required(1)
def admin_gps_dispositivo_delete(id_disp):
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE dispositivo_gps SET activo=FALSE WHERE id_dispositivo=%s", (id_disp,))
        conn.commit(); cur.close()
        flash('Dispositivo desactivado.', 'exito')
    except Exception:
        conn.rollback(); flash('Error.', 'error')
    finally:
        release_db(conn)
    return redirect(url_for('admin_gps'))


@app.route('/admin/gps/zona/nueva', methods=['POST'])
@rol_required(1)
def admin_gps_zona_nueva():
    nombre = request.form.get('nombre', '').strip()
    lat    = request.form.get('latitud',  type=float)
    lon    = request.form.get('longitud', type=float)
    radio  = request.form.get('radio_m',  type=int)
    tipo   = request.form.get('tipo', 'peligrosa')
    if not nombre or lat is None or lon is None or not radio:
        flash('Todos los campos de la zona son obligatorios.', 'error')
        return redirect(url_for('admin_gps'))
    color = '#EF4444' if tipo == 'peligrosa' else '#22C55E'
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO zona_gps (nombre, latitud, longitud, radio_m, tipo, color)
            VALUES (%s,%s,%s,%s,%s,%s)
        """, (nombre, lat, lon, radio, tipo, color))
        conn.commit(); cur.close()
        flash('Zona de geocerca creada.', 'exito')
    except Exception:
        conn.rollback(); flash('Error al crear zona.', 'error')
    finally:
        release_db(conn)
    return redirect(url_for('admin_gps'))


@app.route('/admin/gps/zona/<int:id_zona>/delete', methods=['POST'])
@rol_required(1)
def admin_gps_zona_delete(id_zona):
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE zona_gps SET activo=FALSE WHERE id_zona=%s", (id_zona,))
        conn.commit(); cur.close()
        flash('Zona eliminada.', 'exito')
    except Exception:
        conn.rollback(); flash('Error.', 'error')
    finally:
        release_db(conn)
    return redirect(url_for('admin_gps'))


@app.route('/admin/gps/alerta/<int:id_alerta>/atender', methods=['POST'])
@rol_required(1)
def admin_gps_alerta_atender(id_alerta):
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE alerta_gps SET atendida=TRUE WHERE id_alerta=%s", (id_alerta,))
        conn.commit(); cur.close()
        flash('Alerta marcada como atendida.', 'exito')
    except Exception:
        conn.rollback()
    finally:
        release_db(conn)
    return redirect(url_for('admin_gps'))


# ── Cuidador GPS ──────────────────────────────────────────────────────────────

@app.route('/cuidador/gps')
@rol_required(3)
def cuidador_gps():
    return render_template('cuidador/gps.html')


# ── Familiar GPS ──────────────────────────────────────────────────────────────

@app.route('/familiar/gps')
@familiar_required
def familiar_gps():
    return render_template('familiar/gps.html')


# ─────────────────────────────────────────────────────────────────────────────
#  NFC — Registro de asistencia a actividades
# ─────────────────────────────────────────────────────────────────────────────

@app.route('/api/residentes/lista')
@rol_required(1)
def api_residentes_lista():
    rows = query(
        "SELECT id_residente, nombre, apellidos, habitacion FROM residente WHERE activo=TRUE ORDER BY apellidos, nombre",
        fetchall=True) or []
    return jsonify([dict(r) for r in rows])

@app.route('/nfc/<int:id_residente>')
@csrf.exempt
def nfc_registro(id_residente):
    residente = query(
        "SELECT * FROM residente WHERE id_residente=%s AND activo=TRUE",
        (id_residente,), fetchone=True)
    if not residente:
        return render_template('nfc/no_encontrado.html'), 404

    actividades = query(
        "SELECT * FROM actividad WHERE activo=TRUE ORDER BY nombre",
        fetchall=True) or []

    ultimas = query("""
        SELECT a.ts_registro, act.nombre, act.tipo
        FROM asistencia_nfc a
        JOIN actividad act ON a.id_actividad = act.id_actividad
        WHERE a.id_residente = %s
        ORDER BY a.ts_registro DESC LIMIT 5
    """, (id_residente,), fetchall=True) or []

    return render_template('nfc/registro.html',
                           residente=residente,
                           actividades=actividades,
                           ultimas=ultimas)


@app.route('/nfc/confirmar', methods=['POST'])
@csrf.exempt
def nfc_confirmar():
    id_residente = request.form.get('id_residente', type=int)
    id_actividad = request.form.get('id_actividad', type=int)
    notas        = request.form.get('notas', '').strip() or None

    if not id_residente or not id_actividad:
        return 'Datos incompletos', 400

    # Si hay staff logueado se asocia, si no se registra sin staff
    id_staff = session.get('staff_id')

    conn = get_db()
    id_asistencia = None
    try:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("""
                INSERT INTO asistencia_nfc (id_residente, id_actividad, id_staff, notas, metodo)
                VALUES (%s, %s, %s, %s, 'nfc') RETURNING id_asistencia
            """, (id_residente, id_actividad, id_staff, notas))
            id_asistencia = cur.fetchone()['id_asistencia']
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        logger.error('NFC confirmar error: %s', e)
        return 'Error al registrar', 500
    finally:
        release_db(conn)

    residente  = query("SELECT * FROM residente WHERE id_residente=%s", (id_residente,), fetchone=True)
    actividad  = query("SELECT * FROM actividad  WHERE id_actividad=%s", (id_actividad,), fetchone=True)
    return render_template('nfc/confirmado.html',
                           residente=residente,
                           actividad=actividad,
                           id_asistencia=id_asistencia)


# ── Admin: gestión de actividades ────────────────────────────────────────────

@app.route('/admin/actividades')
@rol_required(1)
def admin_actividades():
    actividades = query("""
        SELECT a.*, COUNT(n.id_asistencia) AS total_asistencias
        FROM actividad a
        LEFT JOIN asistencia_nfc n ON a.id_actividad = n.id_actividad
        GROUP BY a.id_actividad
        ORDER BY a.activo DESC, a.nombre
    """, fetchall=True) or []
    return render_template('admin/actividades.html', actividades=actividades)


@app.route('/admin/nfc/actividad/nueva', methods=['POST'])
@rol_required(1)
def admin_actividad_nueva():
    nombre      = request.form.get('nombre', '').strip()
    tipo        = request.form.get('tipo', 'grupal')
    descripcion = request.form.get('descripcion', '').strip() or None
    if not nombre:
        flash('El nombre es obligatorio', 'error')
        return redirect(url_for('admin_actividades'))
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO actividad (nombre, tipo, descripcion, id_staff_crea)
                VALUES (%s, %s, %s, %s)
            """, (nombre, tipo, descripcion, session.get('staff_id')))
        conn.commit()
        flash(f'Actividad "{nombre}" creada', 'exito')
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        flash('Error al crear actividad', 'error')
        logger.error('admin_actividad_nueva: %s', e)
    finally:
        release_db(conn)
    return redirect(url_for('admin_actividades'))


@app.route('/admin/nfc/actividad/<int:id_act>/toggle', methods=['POST'])
@rol_required(1)
def admin_actividad_toggle(id_act):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE actividad SET activo = NOT activo WHERE id_actividad=%s", (id_act,))
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        logger.error('admin_actividad_toggle: %s', e)
    finally:
        release_db(conn)
    return redirect(url_for('admin_actividades'))


@app.route('/admin/nfc/actividad/<int:id_act>/delete', methods=['POST'])
@rol_required(1)
def admin_actividad_delete(id_act):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM actividad WHERE id_actividad=%s", (id_act,))
        conn.commit()
        flash('Actividad eliminada', 'exito')
    except Exception as e:
        try: conn.rollback()
        except Exception: pass
        flash('No se puede eliminar: tiene asistencias registradas', 'error')
        logger.error('admin_actividad_delete: %s', e)
    finally:
        release_db(conn)
    return redirect(url_for('admin_actividades'))


@app.route('/admin/nfc/asistencias')
@rol_required(1)
def admin_asistencias():
    rows = query("""
        SELECT n.id_asistencia, n.ts_registro, n.metodo, n.notas,
               r.nombre || ' ' || r.apellidos AS residente, r.habitacion,
               act.nombre AS actividad, act.tipo,
               s.nombre || ' ' || s.apellidos AS registrado_por
        FROM asistencia_nfc n
        JOIN residente r   ON n.id_residente = r.id_residente
        JOIN actividad act ON n.id_actividad  = act.id_actividad
        LEFT JOIN staff s  ON n.id_staff      = s.id_staff
        ORDER BY n.ts_registro DESC
        LIMIT 200
    """, fetchall=True) or []
    return render_template('admin/asistencias_nfc.html', rows=rows)


# ── Cuidador: historial de asistencias NFC de sus residentes ─────────────────

@app.route('/cuidador/asistencias-nfc')
@rol_required(3)
def cuidador_asistencias_nfc():
    id_staff = session['staff_id']
    rows = query("""
        SELECT n.ts_registro, n.metodo,
               r.nombre || ' ' || r.apellidos AS residente, r.habitacion,
               act.nombre AS actividad, act.tipo
        FROM asistencia_nfc n
        JOIN residente r   ON n.id_residente = r.id_residente
        JOIN actividad act ON n.id_actividad  = act.id_actividad
        JOIN asignacion a  ON a.id_residente  = r.id_residente
                          AND a.id_staff      = %s
                          AND a.tipo_rol      = 'Cuidador'
                          AND a.fecha_fin IS NULL
        ORDER BY n.ts_registro DESC
        LIMIT 100
    """, (id_staff,), fetchall=True) or []
    return render_template('cuidador/asistencias_nfc.html', rows=rows)



if __name__ == '__main__':
    debug = os.environ.get('FLASK_DEBUG', 'False') == 'True'
    app.run(host='0.0.0.0', debug=debug, port=8080)
