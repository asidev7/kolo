#!/bin/sh
# Applique les migrations avant de démarrer l'API (idempotent).
set -eu

if [ "${KOLO_SKIP_MIGRATE:-0}" != "1" ]; then
    python manage.py migrate --noinput
fi

exec "$@"
