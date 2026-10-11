#!/usr/bin/env bash
# Sauvegarde chiffrée de la base KOLO (déploiement natif, sans Docker).
#
#   /opt/kolo/ops/backup.sh
#
# La phrase de passe vit dans /root/.kolo-backup.env (600, root uniquement).
# Elle doit AUSSI être conservée hors du serveur : sans elle, les sauvegardes
# sont irrécupérables.
set -euo pipefail

DB_NAME="${KOLO_DB_NAME:-kolo}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/kolo}"
RETENTION="${BACKUP_RETENTION_DAYS:-14}"
ENV_FILE="${KOLO_BACKUP_ENV:-/root/.kolo-backup.env}"

# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE absent de $ENV_FILE}"

umask 077
mkdir -p "$BACKUP_DIR"
target="$BACKUP_DIR/kolo-$(date -u +%Y%m%dT%H%M%SZ).sql.gz.gpg"
tmp="$target.partial"

# Le tube passe par gzip puis gpg AES-256 : la base ne touche jamais le disque
# en clair, même transitoirement.
sudo -u postgres pg_dump "$DB_NAME" --no-owner --format=plain \
  | gzip -9 \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-fd 3 --output "$tmp" 3<<<"$BACKUP_PASSPHRASE"
mv "$tmp" "$target"

find "$BACKUP_DIR" -name 'kolo-*.sql.gz.gpg' -type f -mtime +"$RETENTION" -delete
echo "$(date -u +%FT%TZ) Sauvegarde : $target ($(du -h "$target" | cut -f1))"
