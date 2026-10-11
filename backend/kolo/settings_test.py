"""Réglages des tests : production (DEBUG désactivé) avec des valeurs fixes.

`DATABASE_URL` est respectée : la CI fournit PostgreSQL 16 ; sans elle, SQLite
en mémoire.
"""

import os

os.environ.setdefault("DJANGO_SECRET_KEY", "tests-only-secret-key-0123456789abcdef")
os.environ.setdefault("KOLO_ALLOW_SQLITE", "1")
os.environ.setdefault("DJANGO_ALLOWED_HOSTS", "testserver")
os.environ["DJANGO_DEBUG"] = "0"
os.environ["DJANGO_SECURE_SSL_REDIRECT"] = "0"

from .settings import *  # noqa: E402, F403

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]  # tests rapides
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
