"""Configuration Django de KOLO.

Toute valeur sensible ou propre à un environnement vient des variables
d'environnement (voir `.env.example`). Sans `DATABASE_URL`, une base SQLite
locale est utilisée : pratique en développement et pour les tests, jamais en
production (`DJANGO_DEBUG=0` l'interdit).
"""

import os
from datetime import timedelta
from pathlib import Path

import dj_database_url
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent


def env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.environ.get(name, default).split(",") if item.strip()]


DEBUG = env_bool("DJANGO_DEBUG", default=False)

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if not SECRET_KEY:
    if not DEBUG:
        raise ImproperlyConfigured("DJANGO_SECRET_KEY est obligatoire hors développement.")
    SECRET_KEY = "dev-only-insecure-key-never-use-in-production"  # noqa: S105

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,10.0.2.2" if DEBUG else "")

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "apps.core",
    "apps.accounts",
    "apps.categories",
    "apps.transactions",
    "apps.budgets",
    "apps.sync",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "apps.core.middleware.RequestLogMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "kolo.urls"
WSGI_APPLICATION = "kolo.wsgi.application"

# ---------------------------------------------------------------------------
# Base de données
# ---------------------------------------------------------------------------
_database_url = os.environ.get("DATABASE_URL")
if not _database_url and not DEBUG and not env_bool("KOLO_ALLOW_SQLITE"):
    raise ImproperlyConfigured("DATABASE_URL est obligatoire hors développement.")
DATABASES = {
    "default": dj_database_url.parse(
        _database_url or f"sqlite:///{BASE_DIR / 'db.sqlite3'}",
        conn_max_age=int(os.environ.get("DATABASE_CONN_MAX_AGE", "60")),
        conn_health_checks=True,
    )
}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ---------------------------------------------------------------------------
# Comptes
# ---------------------------------------------------------------------------
AUTH_USER_MODEL = "accounts.User"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 8},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# ---------------------------------------------------------------------------
# Internationalisation
# ---------------------------------------------------------------------------
LANGUAGE_CODE = "fr"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

# Fuseau attribué aux nouveaux comptes (ARCHITECTURE.md, D5).
KOLO_DEFAULT_TIMEZONE = "Africa/Porto-Novo"

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "EXCEPTION_HANDLER": "apps.core.exceptions.exception_handler",
    "DEFAULT_THROTTLE_RATES": {
        "auth": os.environ.get("KOLO_THROTTLE_AUTH", "10/min"),
        "password_reset": os.environ.get("KOLO_THROTTLE_PASSWORD_RESET", "5/hour"),
        "sync": os.environ.get("KOLO_THROTTLE_SYNC", "120/min"),
    },
    "UNAUTHENTICATED_USER": None,
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.environ.get("JWT_ACCESS_MINUTES", "15"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=int(os.environ.get("JWT_REFRESH_DAYS", "30"))),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": True,
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "user_id",
    "SIGNING_KEY": os.environ.get("JWT_SIGNING_KEY", SECRET_KEY),
}

# Synchronisation (docs/SYNC.md).
KOLO_SYNC_PUSH_MAX_OPERATIONS = 100
KOLO_SYNC_PULL_DEFAULT_LIMIT = 500
KOLO_SYNC_PULL_MAX_LIMIT = 1000
# Tombstones et opérations traitées effacés après ce délai (PRIVACY.md).
KOLO_TOMBSTONE_RETENTION_DAYS = 90

# Mot de passe oublié : code à 6 chiffres envoyé par e-mail.
KOLO_PASSWORD_RESET_CODE_MINUTES = 15
KOLO_PASSWORD_RESET_MAX_ATTEMPTS = 5

# ---------------------------------------------------------------------------
# E-mail
# ---------------------------------------------------------------------------
EMAIL_BACKEND = os.environ.get(
    "EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend"
    if DEBUG
    else "django.core.mail.backends.smtp.EmailBackend",
)
EMAIL_HOST = os.environ.get("EMAIL_HOST", "")
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", "587"))
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", default=True)
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", "KOLO <no-reply@localhost>")

# ---------------------------------------------------------------------------
# Sécurité HTTP (TLS terminé par Nginx)
# ---------------------------------------------------------------------------
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", default=not DEBUG)
SECURE_REDIRECT_EXEMPT = [r"^api/v1/health$"]
SECURE_HSTS_SECONDS = 0 if DEBUG else 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
DATA_UPLOAD_MAX_MEMORY_SIZE = 1024 * 1024  # 1 Mo : un lot de 100 opérations tient largement.

SILENCED_SYSTEM_CHECKS = [
    # API authentifiée uniquement par en-tête `Authorization: Bearer` : ni
    # cookie ni session, donc rien qu'une requête intersite puisse réutiliser.
    "security.W003",
    # L'inscription du domaine à la liste HSTS preload est une décision de
    # l'exploitant, pas du code.
    "security.W021",
]

CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}

# ---------------------------------------------------------------------------
# Journaux : jamais de montant, de note ni de corps de requête (PRIVACY.md).
# ---------------------------------------------------------------------------
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": os.environ.get("LOG_LEVEL", "INFO")},
    "loggers": {
        # Les requêtes en erreur sont déjà journalisées (sans corps) par
        # RequestLogMiddleware ; le logger Django y ajouterait des détails.
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "django.db.backends": {"level": "WARNING"},
    },
}
