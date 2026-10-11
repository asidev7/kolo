#!/usr/bin/env bash
# Déploie une nouvelle version du backend sur le VPS (déploiement natif).
# À lancer depuis le poste de développement :  bash deploy/native/maj.sh
#
# Le code part par tar sur le canal SSH (rsync n'est pas installé sous Windows).
# Limite connue : les fichiers supprimés côté dépôt restent sur le serveur.
set -euo pipefail

SRV="${KOLO_SRV:-myvps}"
APP_DIR=/var/www/kolo
cd "$(dirname "$0")/../.."

[ -d backend ] || { echo "Dossier backend introuvable." >&2; exit 1; }

echo "== Envoi du code =="
tar czf - \
    --exclude='.venv' --exclude='__pycache__' --exclude='*.pyc' \
    --exclude='db.sqlite3' --exclude='.pytest_cache' --exclude='.ruff_cache' \
    backend \
  | ssh "$SRV" "tar xzf - -C $APP_DIR --strip-components=1 && chown -R kolo:kolo $APP_DIR"
echo "   code en place"

echo "== Dépendances et migrations =="
ssh "$SRV" "sudo -u kolo bash -c 'cd $APP_DIR && set -a && . ./.env && set +a && \
    venv/bin/pip install --quiet -r requirements.txt && \
    venv/bin/python manage.py migrate --noinput'"

echo "== Redémarrage =="
ssh "$SRV" "systemctl restart kolo && sleep 3 && systemctl is-active kolo"
echo "Déploiement terminé."
