"""Tests para autenticacion y control de acceso."""
from unittest.mock import patch
from werkzeug.security import generate_password_hash

ADMIN_USER = {
    'id_usuario': 1,
    'id_staff': 1,
    'nombre': 'Carlos',
    'apellidos': 'Medina Ortiz',
    'especialidad': 'Administrador',
    'nivel_acceso': 1,
    'password_hash': generate_password_hash('admin123'),
}

TERAPEUTA_USER = {
    'id_usuario': 2,
    'id_staff': 2,
    'nombre': 'Juan',
    'apellidos': 'Ramirez',
    'especialidad': 'Psicologo',
    'nivel_acceso': 2,
    'password_hash': generate_password_hash('terapeuta123'),
}

CUIDADOR_USER = {
    'id_usuario': 4,
    'id_staff': 4,
    'nombre': 'Maria',
    'apellidos': 'Lopez',
    'especialidad': 'Cuidadora',
    'nivel_acceso': 3,
    'password_hash': generate_password_hash('cuidador123'),
}


class TestLoginPage:
    def test_login_page_carga(self, client):
        r = client.get('/login')
        assert r.status_code == 200
        assert b'ElderCare' in r.data

    def test_login_redirige_si_ya_autenticado(self, client):
        with client.session_transaction() as sess:
            sess['user_id'] = 1
            sess['nivel_acceso'] = 1
        r = client.get('/login', follow_redirects=False)
        assert r.status_code == 302

    def test_login_campos_vacios(self, client):
        r = client.post('/login', data={'username': '', 'password': ''})
        assert r.status_code == 200
        assert 'obligatorios' in r.data.decode('utf-8')

    def test_login_usuario_no_existe(self, client):
        with patch('app.call_refcursor', return_value=[]):
            r = client.post('/login', data={
                'username': 'noexiste',
                'password': 'cualquier'
            })
        assert r.status_code == 200
        assert 'incorrectos' in r.data.decode('utf-8')

    def test_login_contrasena_incorrecta(self, client):
        with patch('app.call_refcursor', return_value=[ADMIN_USER]):
            r = client.post('/login', data={
                'username': 'admin',
                'password': 'contrasena_mal'
            })
        assert r.status_code == 200
        assert 'incorrectos' in r.data.decode('utf-8')

    def test_login_admin_exitoso(self, client):
        with patch('app.call_refcursor', return_value=[ADMIN_USER]):
            with patch('app.call_proc', return_value=(1, 'ok')):
                r = client.post('/login', data={
                    'username': 'admin',
                    'password': 'admin123'
                }, follow_redirects=False)
        assert r.status_code == 302
        assert '/admin/dashboard' in r.headers.get('Location', '')

    def test_login_terapeuta_redirige_a_su_portal(self, client):
        with patch('app.call_refcursor', return_value=[TERAPEUTA_USER]):
            with patch('app.call_proc', return_value=(1, 'ok')):
                r = client.post('/login', data={
                    'username': 'jramirez',
                    'password': 'terapeuta123'
                }, follow_redirects=False)
        assert r.status_code == 302
        assert '/terapeuta/dashboard' in r.headers.get('Location', '')

    def test_login_cuidador_redirige_a_su_portal(self, client):
        with patch('app.call_refcursor', return_value=[CUIDADOR_USER]):
            with patch('app.call_proc', return_value=(1, 'ok')):
                r = client.post('/login', data={
                    'username': 'mlopez',
                    'password': 'cuidador123'
                }, follow_redirects=False)
        assert r.status_code == 302
        assert '/cuidador/dashboard' in r.headers.get('Location', '')


class TestLogout:
    def test_logout_limpia_sesion(self, client):
        with client.session_transaction() as sess:
            sess['user_id'] = 1
            sess['nivel_acceso'] = 1
        client.get('/logout')
        with client.session_transaction() as sess:
            assert 'user_id' not in sess

    def test_logout_redirige_a_login(self, client):
        r = client.get('/logout', follow_redirects=False)
        assert r.status_code == 302
        assert '/login' in r.headers.get('Location', '')


class TestRBAC:
    def test_admin_accede_admin_dashboard(self, client):
        with client.session_transaction() as sess:
            sess.update({'user_id': 1, 'staff_id': 1, 'nivel_acceso': 1,
                         'user_name': 'Admin', 'user_role': 'Administrador'})
        with patch('app.call_refcursor', return_value=[{}]):
            with patch('app.query', return_value=[]):
                r = client.get('/admin/dashboard')
        assert r.status_code == 200

    def test_cuidador_no_accede_admin(self, client):
        with client.session_transaction() as sess:
            sess.update({'user_id': 4, 'staff_id': 4, 'nivel_acceso': 3,
                         'user_name': 'Maria', 'user_role': 'Cuidadora'})
        r = client.get('/admin/dashboard', follow_redirects=False)
        assert r.status_code == 302

    def test_terapeuta_no_accede_cuidador(self, client):
        with client.session_transaction() as sess:
            sess.update({'user_id': 2, 'staff_id': 2, 'nivel_acceso': 2,
                         'user_name': 'Juan', 'user_role': 'Psicologo'})
        r = client.get('/cuidador/dashboard', follow_redirects=False)
        assert r.status_code == 302

    def test_sin_sesion_redirige_a_login(self, client):
        for ruta in ['/admin/dashboard', '/terapeuta/dashboard', '/cuidador/dashboard']:
            r = client.get(ruta, follow_redirects=False)
            assert r.status_code == 302
            assert '/login' in r.headers.get('Location', '')


class TestErrorHandlers:
    def test_404_retorna_pagina_personalizada(self, client):
        r = client.get('/ruta-que-no-existe-jamas')
        assert r.status_code == 404
        assert b'404' in r.data
