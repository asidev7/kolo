"""Vérifie le parcours complet de l'API en production via HTTPS public.

À lancer depuis le serveur :
    ssh myvps 'KOLO_VERIF_PASSWORD=… python3 -' < deploy/native/verif-https.py
Exerce : inscription (idempotente), connexion, profil, push d'une opération,
pull. Le compte de test (verif-deploiement@) est un compte jetable dédié.
"""

import json
import os
import urllib.error
import urllib.request
import uuid

BASE = "https://api.asitechsolution.cloud/api/v1"
EMAIL = "verif-deploiement@asitechsolution.cloud"

# Le mot de passe du compte de vérification n'est jamais écrit ici : le dépôt
# est public. Il se lit dans l'environnement.
PASSWORD = os.environ.get("KOLO_VERIF_PASSWORD")
if not PASSWORD:
    raise SystemExit(
        "KOLO_VERIF_PASSWORD absent : exporter le mot de passe du compte "
        f"{EMAIL} avant de lancer ce script."
    )


def call(method, path, payload=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def show(label, status, body=""):
    detail = body[:120].replace("\n", " ") if body else ""
    print(f"  {label:<24} HTTP {status}  {detail}")


print("Parcours de vérification KOLO (HTTPS public)\n")

# 1. Connexion (le compte de vérif existe déjà depuis le premier déploiement).
status, body = call("POST", "/auth/login", {"email": EMAIL, "password": PASSWORD})
if status == 401:
    show("connexion", status, "compte absent → inscription")
    status, body = call("POST", "/auth/register",
                        {"email": EMAIL, "password": PASSWORD, "first_name": "Vérif"})
    show("inscription", status, body)
    status, body = call("POST", "/auth/login", {"email": EMAIL, "password": PASSWORD})
    show("connexion (après insc.)", status, body)
else:
    show("connexion (JWT)", status, body)

if status != 200:
    raise SystemExit("connexion impossible — arrêt")

token = json.loads(body)["access"]

show("profil (/auth/me)", *call("GET", "/auth/me", token=token))

# 2. Écriture : push d'une opération de test (montant 1500 F CFA).
op_id = str(uuid.uuid4())
entity_id = str(uuid.uuid4())
payload = {
    "device_id": "verif-deploiement",
    "operations": [{
        "op_id": op_id,
        "entity": "transaction",
        "entity_id": entity_id,
        "op_type": "upsert",
        "base_version": 0,
        "changed_fields": ["amount", "note"],
        "data": {
            "type": "expense",
            "amount": 1500,
            "currency": "XOF",
            "category_id": "c0a7e9e0-0000-4000-8000-000000000002",
            "note": "verif-deploiement",
            "occurred_on": "2026-10-11",
        },
    }],
}
status, body = call("POST", "/sync/push", payload, token=token)
show("push (opération)", status, body)

# 3. Lecture : pull complet.
status, body = call("GET", "/sync/pull?cursor=0&limit=1000", token=token)
show("pull (cursor=0)", status, body[:120])

# 4. Sans jeton : attendu 401.
show("pull sans jeton (401)", *call("GET", "/sync/pull"))

print("\nTerminé.")
