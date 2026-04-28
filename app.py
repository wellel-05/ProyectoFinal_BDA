import os
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
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool
from werkzeug.security import check_password_hash, generate_password_hash

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
}

_pool: 'ThreadedConnectionPool | None' = None

def _get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = ThreadedConnectionPool(minconn=2, maxconn=10, **DB_CONFIG)
        logger.info('Pool de conexiones inicializado (min=2, max=10)')
    return _pool

def get_db():
    try:
        return _get_pool().getconn()
    except psycopg2.pool.PoolError as e:
        logger.critical('Pool de conexiones agotado: %s', e)
        raise

def release_db(conn):
    _get_pool().putconn(conn)

# ── DB helpers ────────────────────────────────────────────────────────────────

def query(sql, params=None, fetchone=False, fetchall=False):
    conn = get_db()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(sql, params or ())
        result = None
        if fetchone:   result = cur.fetchone()
        elif fetchall: result = cur.fetchall()
        cur.close()
        return result
    except Exception as e:
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
        conn.commit()
        row = cur.fetchone()
        return (int(row[0]), str(row[1])) if row else (0, 'Sin respuesta del servidor.')
    except Exception as e:
        conn.rollback()
        logger.error('call_proc error [%.80s]: %s', sql, e)
        return (0, 'Error interno del servidor.')
    finally:
        cur.close()
        release_db(conn)

def call_refcursor(sql, params=()):
    """Llama un procedimiento que abre un REFCURSOR llamado 'resultado'."""
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("BEGIN")
        cur.execute(sql, params)
        cur.execute("FETCH ALL FROM resultado")
        rows = cur.fetchall()
        cur.execute("COMMIT")
        return rows
    except Exception as e:
        try: cur.execute("ROLLBACK")
        except: pass
        logger.error('refcursor error [%.80s]: %s', sql, e)
        return []
    finally:
        cur.close()
        release_db(conn)

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
            {'endpoint': 'admin_reportes',   'icon': 'fa-file-chart-column','label': 'Reportes'},
            {'endpoint': 'admin_auditoria',  'icon': 'fa-list-check',       'label': 'Auditoria'},
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
            {'endpoint': 'cuidador_nfc',          'icon': 'fa-mobile-screen', 'label': 'Escaneo NFC'},
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
    if 'user_id' in session:
        return redirect(url_for('index'))

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

    return render_template('admin/residente_detalle.html',
                           residente=residente,
                           asignaciones=asignaciones,
                           sesiones=sesiones,
                           checkins=checkins,
                           incidentes=incidentes)

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
    return redirect(url_for('admin_rfid'))

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

    log_nfc = call_refcursor(
        "CALL sp_log_nfc_hoy(%s, 'resultado')", (id_staff,))

    return render_template('cuidador/nfc.html',
                           tags_nfc=tags_nfc,
                           resultado=resultado,
                           log_nfc=log_nfc)


# ── NFC — escaneo desde iPhone ───────────────────────────────────────────────

@app.route('/nfc/<codigo_tag>')
@login_required
def nfc_scan_tag(codigo_tag):
    tag = query(
        "SELECT * FROM nfc_tag WHERE codigo_tag = %s",
        (codigo_tag,), fetchone=True
    )
    if not tag:
        return render_template('nfc_scan.html', error='Tag no registrado en el sistema.', codigo=codigo_tag)

    residente = query(
        """SELECT r.*, s.nombre AS sala_nombre
           FROM residente r
           LEFT JOIN sala s ON r.id_sala = s.id_sala
           WHERE r.id_residente = %s""",
        (tag['id_residente'],), fetchone=True
    )

    meds = query(
        """SELECT m.nombre, md.dosis, md.hora_programada,
                  COALESCE(
                      (SELECT TRUE FROM log_medicamento lm
                       WHERE lm.id_med_diario = md.id_med_diario
                         AND lm.fecha_administracion::date = CURRENT_DATE
                       LIMIT 1),
                      FALSE
                  ) AS administrado
           FROM medicamento_diario md
           JOIN medicamento m ON md.id_medicamento = m.id_medicamento
           WHERE md.id_residente = %s AND md.activo = TRUE
           ORDER BY md.hora_programada""",
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
        return redirect(url_for('admin_nfc'))

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

    return redirect(url_for('admin_nfc'))


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
    return redirect(url_for('admin_nfc'))


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
        cur = conn.cursor(cursor_factory=RealDictCursor)
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


if __name__ == '__main__':
    debug = os.environ.get('FLASK_DEBUG', 'False') == 'True'
    app.run(debug=debug, port=8080)
