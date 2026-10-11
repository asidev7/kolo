#!/usr/bin/env bash
# Installation native de l'API KOLO (Ubuntu/Debian, sans Docker).
# À lancer en root depuis n'importe où : bash install.sh
#
# Prévoit un utilisateur système « kolo », une base PostgreSQL dédiée, un venv
# Python et un fichier .env dont les secrets sont générés SUR le serveur (ils ne
# transitent donc jamais par un poste de travail).
set -euo pipefail

APP_DIR=/var/www/kolo
APP_USER=kolo
DB_NAME=kolo
DB_ROLE=kolo
DOMAIN=api.asitechsolution.cloud

if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être lancé en root." >&2
    exit 1
fi

cd "$APP_DIR"

echo "== 1/5  Dépendances Python, PostgreSQL et venv =="
command -v python3 >/dev/null || { echo "python3 absent" >&2; exit 1; }
command -v psql >/dev/null || { echo "psql absent" >&2; exit 1; }
# python3-venv et libpq ne sont requis que si le venv ou psycopg manquent.
if [ ! -x venv/bin/python ] || ! python3 -c 'import venv' 2>/dev/null; then
    apt-get install -y --no-install-recommends python3-venv
fi

echo "== 2/5  Environnement virtuel et dépendances =="
[ -x venv/bin/python ] || python3 -m venv venv
venv/bin/pip install --quiet --upgrade pip
venv/bin/pip install --quiet -r requirements.txt
echo "   $(venv/bin/python --version), $(venv/bin/pip list --format=freeze | wc -l) paquets"

echo "== 3/5  Base de données et configuration =="
if [ -f .env ]; then
    echo "   .env déjà présent : conservé tel quel"
else
    DB_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    DJANGO_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
    JWT_SIGNING_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"

    su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_ROLE}'\" | grep -q 1" \
        || su - postgres -c "psql -c \"CREATE ROLE ${DB_ROLE} LOGIN PASSWORD '${DB_PASSWORD}'\""
    su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\" | grep -q 1" \
        || su - postgres -c "createdb --owner=${DB_ROLE} --encoding=UTF8 ${DB_NAME}"

    # Écrit par python (jamais par le shell) : aucune valeur n'apparaît dans la
    # sortie du script ni dans un historique de commandes.
    DB_PASSWORD="$DB_PASSWORD" DJANGO_SECRET_KEY="$DJANGO_SECRET_KEY" \
    JWT_SIGNING_KEY="$JWT_SIGNING_KEY" DB_NAME="$DB_NAME" DB_ROLE="$DB_ROLE" \
    DOMAIN="$DOMAIN" python3 - <<'PY'
import os, pathlib
env = "\n".join([
    "# KOLO — API. Généré par deploy/native/install.sh, ne pas versionner.",
    f"DJANGO_SECRET_KEY={os.environ['DJANGO_SECRET_KEY']}",
    f"JWT_SIGNING_KEY={os.environ['JWT_SIGNING_KEY']}",
    f"DJANGO_ALLOWED_HOSTS={os.environ['DOMAIN']}",
    "DJANGO_DEBUG=0",
    "DATABASE_URL=postgres://{u}:{p}@127.0.0.1:5432/{d}".format(
        u=os.environ["DB_ROLE"], p=os.environ["DB_PASSWORD"], d=os.environ["DB_NAME"]),
    "DEFAULT_FROM_EMAIL=\"KOLO <no-reply@asitechsolution.cloud>\"",
    "",
])
pathlib.Path(".env").write_bytes(env.encode("utf-8"))
PY
    echo "   .env généré (secrets créés sur le serveur)"
fi

chmod 600 .env
chown -R "${APP_USER}:${APP_USER}" "$APP_DIR"

echo "== 4/5  Migrations =="
# sudo réinitialise l'environnement : le .env est donc relu sous l'utilisateur
# applicatif (qui seul peut lire le fichier 600) au lieu d'être transmis par
# l'environnement de root — les secrets ne traversent ainsi aucune ligne de
# commande.
as_app() { sudo -u "$APP_USER" bash -c "cd $APP_DIR && set -a && . ./.env && set +a && exec $*"; }
as_app venv/bin/python manage.py migrate --noinput
as_app venv/bin/python manage.py check --deploy --fail-level ERROR

echo "== 5/5  Terminé =="
echo "   Application  : $APP_DIR"
echo "   Base          : $DB_NAME (PostgreSQL local)"
echo "   Étapes restantes : kolo.service (systemd), vhost Nginx, certbot."
