import os
import pytest

# Variables de entorno antes de importar app para evitar errores de configuracion
os.environ.setdefault('SECRET_KEY', 'clave-secreta-para-tests-pytest')
os.environ.setdefault('DB_HOST', 'localhost')
os.environ.setdefault('DB_NAME', 'asilo_db_test')
os.environ.setdefault('DB_USER', 'test_user')
os.environ.setdefault('DB_PASSWORD', 'test_password')
os.environ.setdefault('WTF_CSRF_ENABLED', 'False')

import app as app_module


@pytest.fixture
def application():
    app_module.app.config['TESTING'] = True
    app_module.app.config['WTF_CSRF_ENABLED'] = False
    return app_module.app


@pytest.fixture
def client(application):
    return application.test_client()
