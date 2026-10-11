#!/usr/bin/env bash
# Restaure une sauvegarde chiffrée DANS UNE BASE KOLO VIDE.
#
#   /opt/kolo/ops/restore.sh /var/backups/kolo/kolo-20261011T020000Z.sql.gz.gpg
#
# Après restauration, les téléphones dont le curseur de synchronisation est plus
# récent que la sauvegarde reçoivent « 410 cursor_reset_required », refont un
# pull complet et renvoient leur outbox : aucune opération n'est perdue côté
# client (docs/SYNC.md §9).
set -euo pipefail

file="${1:?Fichier de sauvegarde attendu}"
DB_NAME="${KOLO_DB_NAME:-kolo}"
ENV_FILE="${KOLO_BACKUP_ENV:-/root/.kolo-backup.env}"

# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE absent de $ENV_FILE}"

gpg --batch --decrypt --passphrase-fd 3 "$file" 3<<<"$BACKUP_PASSPHRASE" \
  | gunzip \
  | sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME"
echo "Restauration terminée dans la base $DB_NAME."
