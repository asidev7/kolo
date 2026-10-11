#!/usr/bin/env bash
# Tâches quotidiennes de l'API KOLO (appelées par le cron de l'hôte) :
# purge des tombstones et des jetons expirés, puis sauvegarde chiffrée.
#
#   /opt/kolo/ops/daily.sh        (cron : 15 3 * * *)
set -euo pipefail

APP_DIR=/var/www/kolo
OPS_DIR="$(dirname "$0")"

# sudo réinitialise l'environnement : le .env est relu sous l'utilisateur
# applicatif, seul autorisé à lire ce fichier en 600.
as_app() {
    sudo -u kolo bash -c "cd $APP_DIR && set -a && . ./.env && set +a && exec $*"
}

echo "--- purge des donnees de synchronisation ---"
as_app venv/bin/python manage.py purge_sync_data

echo "--- purge des jetons expires ---"
as_app venv/bin/python manage.py flushexpiredtokens

echo "--- sauvegarde ---"
"$OPS_DIR/backup.sh"
