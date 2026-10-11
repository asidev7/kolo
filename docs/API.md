# API KOLO — v1

> Backend Django REST Framework (phase 4). Base : `https://<domaine>/api/v1/`.
> JSON uniquement (`Content-Type: application/json`, UTF-8). Le protocole de
> synchronisation est détaillé dans [SYNC.md](SYNC.md).

## Conventions

| Sujet | Règle |
|---|---|
| Authentification | `Authorization: Bearer <access>` (JWT). Access 15 min, refresh 30 jours, rotation à chaque refresh. |
| Horodatages | ISO-8601 UTC à la milliseconde, suffixe `Z` : `2026-10-09T23:41:03.531Z` (D11). |
| Montants | Entiers, plus petite unité de la devise (1 = 1 F CFA). Jamais de décimal. |
| Identifiants | UUID v4 en texte. Les enregistrements synchronisés ont un `id` choisi par le téléphone. |
| Erreurs | Toujours le même format (ci-dessous). `code` est stable, `message` est en français simple et affichable. |

```json
{"error": {"code": "validation_error",
           "message": "Certaines informations ne sont pas valides.",
           "fields": {"email": ["Un compte existe déjà avec cette adresse."]}}}
```

| HTTP | `code` | Sens pour le client |
|---|---|---|
| 400 | `validation_error`, `parse_error`, `invalid_code`, `invalid_credentials` (changement de mot de passe) | corriger la saisie |
| 401 | `not_authenticated`, `token_not_valid` | rafraîchir la session une fois, sinon écran de connexion |
| 401 | `invalid_credentials` | identifiants incorrects (message générique) |
| 404 / 405 | `not_found`, `method_not_allowed` | erreur de programmation |
| 410 | `cursor_reset_required` | refaire un pull complet depuis le curseur `0` |
| 429 | `throttled` | réessayer plus tard |
| 500 | `server_error` | réessayable (backoff) |

## Santé

`GET /health` — sans authentification. `200 {"status": "ok", "server_time": "…"}`.

## Comptes — `/auth/`

| Méthode et chemin | Corps | Réponse |
|---|---|---|
| `POST /auth/register` | `email`, `password`, `first_name` | `201` session |
| `POST /auth/login` | `email`, `password` | `200` session · `401 invalid_credentials` |
| `POST /auth/refresh` | `refresh` | `200 {access, refresh}` · `401 token_not_valid` |
| `POST /auth/logout` | `refresh` | `204` (toujours, même si le jeton est déjà invalide) |
| `GET /auth/me` | — | `200` utilisateur |
| `PATCH /auth/me` | `first_name`, `timezone` | `200` utilisateur (l'adresse e-mail n'est pas modifiable) |
| `POST /auth/password/change` | `current_password`, `new_password` | `200` session neuve ; les autres appareils sont déconnectés |
| `POST /auth/password/forgot` | `email` | `202` (toujours : ne révèle pas si le compte existe) |
| `POST /auth/password/reset` | `email`, `code` (6 chiffres), `new_password` | `204` ; toutes les sessions sont révoquées |

Session :

```json
{"user": {"id": "…", "email": "awa@example.com", "first_name": "Awa",
          "timezone": "Africa/Porto-Novo"},
 "access": "eyJ…", "refresh": "eyJ…"}
```

- L'adresse e-mail est enregistrée en minuscules ; la connexion ignore la casse.
- Mot de passe : 8 caractères minimum, pas entièrement numérique, pas trop
  courant, pas trop proche de l'adresse ou du prénom.
- Refresh : l'ancien refresh token est mis en liste noire. **Un seul refresh
  concurrent** côté client (SYNC.md §6) : deux refresh parallèles du même jeton
  font échouer le second.
- Mot de passe oublié : code à 6 chiffres envoyé par e-mail, valable 15 min,
  5 essais, à usage unique ; une nouvelle demande invalide le code précédent.
- Limitation de débit : 10/min sur inscription, connexion et changement de mot
  de passe ; 5/heure sur mot de passe oublié et réinitialisation ; 120/min sur
  la synchronisation. Nginx ajoute une limite par adresse IP.

## Synchronisation — `/sync/`

### `POST /sync/push`

```json
{"device_id": "installation-id",
 "operations": [{"op_id": "…", "entity": "transaction", "entity_id": "…",
                 "op_type": "upsert", "base_version": 0,
                 "changed_fields": ["amount", "note"],
                 "data": {"type": "expense", "amount": 1500, "currency": "XOF",
                          "category_id": "c0a7e9e0-0000-4000-8000-000000000002",
                          "note": "Zém", "occurred_on": "2026-10-09"}}]}
```

100 opérations maximum par requête (sinon `400`, rien n'est appliqué). Réponse
`200`, un résultat par opération **dans l'ordre reçu** :

```json
{"results": [
   {"op_id": "…", "status": "applied", "entity": "transaction", "entity_id": "…",
    "version": 1, "server_updated_at": "…", "deleted_at": null},
   {"op_id": "…", "status": "duplicate", "…": "résultat de la première application"},
   {"op_id": "…", "status": "conflict", "entity": "…", "entity_id": "…",
    "reason": "modified_on_server", "conflicting_fields": ["amount"],
    "server_record": {"entity": "…", "entity_id": "…", "version": 3,
                      "server_updated_at": "…", "deleted_at": null,
                      "change_seq": 12, "data": {"…": "…"}}},
   {"op_id": "…", "status": "rejected", "entity": "…", "entity_id": "…",
    "error": {"code": "validation_error", "message": "…",
              "fields": {"amount": "Montant hors limites."}}}],
 "server_time": "…"}
```

Champs de `data` par entité (identiques à `Payloads` côté mobile) :

| Entité | Champs |
|---|---|
| `transaction` | `type` (`expense`/`income`), `amount` (1 à 999 999 999 999), `currency` (`XOF`), `category_id`, `note` (≤ 140, `null`), `occurred_on` (`YYYY-MM-DD`, du 2000-01-01 à J+1) |
| `category` | `name` (1–40, unique par compte et type sans tenir compte de la casse), `type`, `icon` (clé `[a-z0-9_]`), `color` (`#RRGGBB` ou `null`), `sort_order` |
| `budget` | `period` (`YYYY-MM`), `category_id` (`null` = global), `limit_amount` (≥ 0), `currency`, `alert_thresholds` (1 à 100, sans doublon) |

Codes de rejet : `invalid_operation` (enveloppe illisible), `validation_error`,
`unknown_category`, `duplicate_name`, `duplicate_budget`, `read_only`
(catégorie par défaut), `forbidden` (enregistrement ou `op_id` d'un autre
compte), `invalid_base_version` (version supérieure à celle du serveur).

### `GET /sync/pull?cursor=<n>&limit=<n>`

`cursor` : `0` au premier appel, puis `next_cursor` (texte opaque à stocker
tel quel). `limit` : 500 par défaut, 1 000 maximum.

```json
{"changes": [{"entity": "category", "entity_id": "…", "version": 2,
              "server_updated_at": "…", "deleted_at": null, "change_seq": 7,
              "data": {"…": "…"}}],
 "next_cursor": "7", "has_more": false, "server_time": "…"}
```

- Seuls les enregistrements du compte sont renvoyés ; les catégories par défaut
  ne le sont jamais (le téléphone les crée avec les mêmes UUID).
- Chaque enregistrement apparaît une fois, dans son dernier état ; un
  enregistrement supprimé arrive avec `deleted_at` renseigné.
- Dans une page : catégories, puis budgets, puis opérations.
- `410 cursor_reset_required` : le curseur précède une purge (tombstones de
  plus de 90 jours) ou dépasse l'état du serveur (restauration d'une
  sauvegarde). Le client repart de `cursor=0`.
