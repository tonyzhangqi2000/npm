import os
import base64

from nsot.conf.settings import *

PG_PASSWORD = os.environ.get('PG_PASSWORD', '123456')
PG_HOST = os.environ.get('PG_HOST', 'postgres')

DEBUG = False

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'USER': 'nsot',
        'NAME': 'nsot',
        'PASSWORD': PG_PASSWORD,
        'HOST': PG_HOST,
        'PORT': '5432',
    },
}

NSOT_HOST = '0.0.0.0'
NSOT_PORT = 8990
NSOT_NUM_WORKERS = 4
NSOT_WORKER_TIMEOUT = 30
SERVE_STATIC_FILES = True

SECRET_KEY = base64.urlsafe_b64encode(os.urandom(32))

USER_AUTH_HEADER = 'X-NSoT-Email'
AUTH_TOKEN_EXPIRY = 600  # 10 minutes
ALLOWED_HOSTS = ['*']
