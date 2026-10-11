# Déploiement natif de l'API KOLO

Ce dossier décrit le déploiement **réellement en service** sur le VPS
`72.62.181.25` (hôte `srv1254746`, Ubuntu 25.10) : une installation native
(venv + gunicorn + systemd), **sans Docker**.

> Pourquoi pas `deploy/docker-compose.yml` ? Le VPS est mutualisé : Nginx y
> tourne déjà sur l'hôte (ports 80 et 443), Mailu occupe les ports de
> messagerie, et une douzaine d'applications y suivent le même modèle
> `/var/www/<app>` + service systemd. Le conteneur `nginx` du compose ne
> pourrait jamais publier 80/443, et activer `ufw` couperait le mail. Ce
> déploiement s'aligne donc sur la convention du serveur.

## Vue d'ensemble

```
/var/www/kolo/            code, propriétaire kolo:kolo
/var/www/kolo/.env        secrets (600) — générés sur le serveur
/var/www/kolo/venv/       environnement Python 3.13
/opt/kolo/ops/            scripts d'exploitation (backup.sh, restore.sh)
/root/.kolo-backup.env    phrase de passe des sauvegardes (600, root)

gunicorn --bind 127.0.0.1:8110      jamais exposé directement
kolo.service                        systemd, activé au démarrage
/etc/nginx/sites-available/kolo     vhost api.asitechsolution.cloud
PostgreSQL 17 (hôte)  base « kolo » rôle « kolo »
```

## Fichiers

| Fichier | Destination | Rôle |
|---|---|---|
| `install.sh` | exécuté en root sur le VPS | venv, base, `.env`, migrations |
| `kolo.service` | `/etc/systemd/system/` | unité systemd |
| `nginx-kolo.conf` | `/etc/nginx/sites-available/kolo` | vhost |
| `nginx-proxy-params.conf` | `/etc/nginx/proxy_params_kolo` | en-têtes de proxy |
| `backup.sh` | `/opt/kolo/ops/` | sauvegarde chiffrée |
| `restore.sh` | `/opt/kolo/ops/` | restauration |
| `maj.sh` | lançé depuis le poste | déploie une nouvelle version |
| `verif-api.py` | exécuté sur le VPS | vérifie le parcours API |

## Installation initiale (déjà faite)

```bash
bash deploy/native/install.sh                      # sur le VPS, en root
install -m 644 deploy/native/kolo.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now kolo
install -m 644 deploy/native/nginx-kolo.conf /etc/nginx/sites-available/kolo
ln -s /etc/nginx/sites-available/kolo /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

## Certificat TLS

`api.asitechsolution.cloud` doit d'abord résoudre vers `72.62.181.25`
(enregistrement `A` chez Hostinger, sans proxy CDN). Ensuite :

```bash
certbot --nginx -d api.asitechsolution.cloud
```

## Mise à jour

```bash
bash deploy/native/maj.sh          # depuis le poste de développement
```

## Sauvegardes

```bash
/opt/kolo/ops/backup.sh                                        # manuelle
/opt/kolo/ops/restore.sh /var/backups/kolo/kolo-<date>.sql.gz.gpg
```

Format `.sql.gz.gpg` (AES-256), conservées 14 jours dans `/var/backups/kolo`.
**La phrase de passe (`/root/.kolo-backup.env`) doit être conservée hors du
serveur** : sans elle, les sauvegardes sont irrécupérables.

## Dépannage

```bash
systemctl status kolo                 # état du service
journalctl -u kolo -n 50              # journaux récents
curl -H 'Host: api.asitechsolution.cloud' http://127.0.0.1:8110/api/v1/health
```

Les journaux ne contiennent jamais de montant, de note, d'adresse e-mail ni de
jeton (PRIVACY.md).
