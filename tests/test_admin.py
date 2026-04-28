"""Tests para el portal administrador."""
from unittest.mock import patch


def set_admin_session(client):
    with client.session_transaction() as sess:
        sess.update({
            'user_id': 1, 'staff_id': 1, 'nivel_acceso': 1,
            'user_name': 'Carlos Medina', 'user_role': 'Administrador',
        })


MOCK_STATS = {
    'total_residentes': 4, 'total_staff': 6,
    'incidentes_alta': 1, 'meds_pendientes': 2,
}


class TestAdminDashboard:
    def test_dashboard_carga(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[MOCK_STATS]):
            with patch('app.query', return_value=[]):
                r = client.get('/admin/dashboard')
        assert r.status_code == 200

    def test_dashboard_sin_datos_no_rompe(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            with patch('app.query', return_value=[]):
                r = client.get('/admin/dashboard')
        assert r.status_code == 200


class TestAdminResidentes:
    def test_lista_residentes(self, client):
        set_admin_session(client)
        with patch('app.query', return_value=[]):
            r = client.get('/admin/residentes')
        assert r.status_code == 200

    def test_formulario_nuevo_residente_carga(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            r = client.get('/admin/residentes/nuevo')
        assert r.status_code == 200

    def test_crear_residente_campos_vacios_falla(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            r = client.post('/admin/residentes/nuevo', data={
                'nombre': '', 'apellidos': '',
                'fecha_nacimiento': '', 'sexo': '',
            })
        assert r.status_code == 200

    def test_crear_residente_exitoso(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            with patch('app.call_proc', return_value=(1, 'Residente registrado.')):
                r = client.post('/admin/residentes/nuevo', data={
                    'nombre': 'Ana', 'apellidos': 'Prueba',
                    'fecha_nacimiento': '1950-01-01', 'sexo': 'F',
                }, follow_redirects=False)
        assert r.status_code == 302

    def test_baja_residente(self, client):
        set_admin_session(client)
        with patch('app.call_proc', return_value=(1, 'Baja registrada.')):
            r = client.post('/admin/residentes/1/baja', follow_redirects=False)
        assert r.status_code == 302


class TestAdminStaff:
    def test_lista_staff(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            r = client.get('/admin/staff')
        assert r.status_code == 200

    def test_crear_staff_campos_vacios_falla(self, client):
        set_admin_session(client)
        r = client.post('/admin/staff/nuevo', data={
            'nombre': '', 'apellidos': '', 'email': '',
            'username': '', 'password': '', 'id_rol': '',
        }, follow_redirects=False)
        assert r.status_code == 302

    def test_toggle_staff(self, client):
        set_admin_session(client)
        with patch('app.call_proc', return_value=(1, 'Estado actualizado.')):
            r = client.post('/admin/staff/1/toggle', follow_redirects=False)
        assert r.status_code == 302


class TestAdminReportes:
    def test_reportes_carga(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            r = client.get('/admin/reportes')
        assert r.status_code == 200

    def test_reportes_con_parametros(self, client):
        set_admin_session(client)
        with patch('app.call_refcursor', return_value=[]):
            r = client.get('/admin/reportes?dias=7&tab=animo')
        assert r.status_code == 200
