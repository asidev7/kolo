"""Vérifie le parcours réel de l'API KOLO depuis le serveur lui-même.

Simule HTTPS (X-Forwarded-Proto) pour contourner la redirection forcée de
Django : cela permet de valider l'API avant même que le certificat TLS existe.
Le compte de test est supprimé par delete-verif.py après coup.

    KOLO_VERIF_PASSWORD='…' python3 /root/verif-api.py
"""

import json
import os
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8110"
HEADERS = {
    "Host": "api.asitechsolution.cloud",
    "X-Forwarded-Proto": "https",
    "Content-Type": "application/json",
}
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
    headers = dict(HEADERS)
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def show(label, status, body=""):
    detail = body[:110].replace("\n", " ") if body else ""
    print(f"  {label:<26} HTTP {status}  {detail}")


print("Parcours de vérification de l'API KOLO\n")

status, body = call("POST", "/api/v1/auth/register",
                    {"email": EMAIL, "password": PASSWORD, "first_name": "Vérif"})
show("inscription", status, body)

status, body = call("POST", "/api/v1/auth/login", {"email": EMAIL, "password": PASSWORD})
show("connexion (JWT)", status, body)
if status != 200:
    raise SystemExit("connexion impossible — arrêt")

token = json.loads(body)["access"]

show("profil (/auth/me)", *call("GET", "/api/v1/auth/me", token=token))
show("tirage (/sync/pull)", *call("GET", "/api/v1/sync/pull", token=token))

status, _ = call("GET", "/api/v1/sync/pull")
print(f"\n  sans jeton (attendu 401)  HTTP {status}")
