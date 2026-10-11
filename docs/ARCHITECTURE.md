# Architecture de KOLO

> Application mobile de finances personnelles **offline-first** — By ASITECH SOLUTION.
> Ce document fait foi pour l'architecture, le modèle de données et les décisions
> techniques. Toute décision nouvelle s'ajoute à la section [Décisions](#décisions).

## 1. Principes

1. **SQLite (Drift) est la source de vérité de l'interface.** Aucun écran ne lit
   l'API. Toutes les lectures sont des streams Drift : une écriture met l'écran à
   jour instantanément.
2. **Le serveur est la source de vérité de la sauvegarde et du multi-appareil.**
   Il attribue les versions (`version`, `server_updated_at`) et l'ordre des
   changements (`change_seq`).
3. **Une opération validée localement n'est jamais perdue** : ni par un échec
   réseau, ni par un crash, ni par un redémarrage. L'outbox et le curseur de
   synchronisation sont persistés en base.
4. **Montants entiers uniquement.** Aucun `double` dans un calcul financier, ni
   côté client ni côté serveur. 1 unité stockée = 1 franc CFA (XOF).
5. **Horloge et identifiants injectés** (`TimeSource`, `IdGenerator`) : tous les
   tests sont déterministes.

## 2. Vue d'ensemble

```
┌──────────────────────────── Application Flutter ────────────────────────────┐
│ presentation  écrans + contrôleurs Riverpod (lisent des streams, jamais l'API)│
│      │                                                                        │
│ domain        entités, validation, calculs financiers — fonctions pures       │
│      │                                                                        │
│ data          repositories : validation → transaction SQLite (métier + outbox)│
│      │                                                                        │
│ database      Drift / SQLite : tables métier, outbox, sync_state, settings    │
│      │                                                                        │
│ synchronization  OutboxWriter (phase 2) · SyncEngine push/pull (phase 5)      │
└──────┼───────────────────────────────────────────────────────────────────────┘
       │ HTTPS, JWT — POST /api/v1/sync/push · GET /api/v1/sync/pull
┌──────▼──────────────── Backend Django REST Framework (phase 4) ──────────────┐
│ PostgreSQL 16 · idempotence (ProcessedOperation) · change_seq monotone        │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Flux d'une écriture (§4.2)

```
Formulaire ──► TransactionValidator (domaine)
           ──► OutboxWriter.transaction(        ← UNE transaction SQLite
                 INSERT/UPDATE transactions
                 + outbox.record(...)            ← seulement si un compte est lié
               )
           ──► streams Drift → l'écran se met à jour
           ──► localWriteSignal()               ← déclenche une synchro (phase 5)
```

`OutboxRecorder` n'existe qu'à l'intérieur de `OutboxWriter.transaction` : il est
**impossible par construction** d'écrire dans l'outbox hors de la transaction de
l'enregistrement métier.

## 3. Pile technique

| Besoin | Choix |
|---|---|
| UI | Flutter 3.47 (stable), Dart 3.13, Material 3 |
| État / DI | Riverpod 3 (`flutter_riverpod`) |
| Navigation | GoRouter 18, redirections pilotées par la session |
| Base locale | Drift 2.35 + SQLite natif (`drift_flutter`) |
| Graphiques | `fl_chart` |
| Notifications | `flutter_local_notifications` (alertes budget, 100 % locales) |
| Connectivité | `connectivity_plus` — indice seulement |
| Tests | `flutter_test`, base Drift en mémoire, `mocktail` |
| Backend | Python 3.12, Django 5.2 LTS, DRF 3.16+, PostgreSQL 16, SimpleJWT (liste noire), Gunicorn |
| Déploiement | Docker Compose (PostgreSQL, API, Nginx TLS), sauvegardes `pg_dump` chiffrées GPG |
| Tests backend | pytest + pytest-django ; SQLite en local, PostgreSQL 16 en CI ; ruff |

## 4. Arborescence

```
kolo/
├── mobile/
│   ├── lib/
│   │   ├── app/                 app.dart, router.dart, bootstrap.dart, home_shell.dart,
│   │   │   │                    providers.dart (repositories + lectures réactives),
│   │   │   │                    app_config.dart (flavors, API_BASE_URL)
│   │   │   └── theme/           kolo_colors, kolo_tokens, kolo_typography, kolo_theme
│   │   ├── core/
│   │   │   ├── constants/       default_categories.dart (UUID fixes), currencies.dart
│   │   │   ├── errors/          Failure + messages en français simple
│   │   │   ├── model/           énumérations et totaux partagés
│   │   │   ├── network/         connectivité (Dio et intercepteurs en phase 5)
│   │   │   ├── providers/       base, horloge, générateur d'UUID, configuration
│   │   │   ├── utils/           LocalDate/YearMonth, money, dates FR, TimeSource
│   │   │   └── widgets/         design system partagé
│   │   ├── database/
│   │   │   ├── app_database.dart  schéma, migrations, seeding des catégories
│   │   │   ├── connection.dart    ouverture du fichier (SQLCipher plus tard ici)
│   │   │   ├── tables/            transactions, categories, budgets, outbox, techniques
│   │   │   └── daos/              requêtes, agrégats SQL, pagination par curseur
│   │   ├── features/
│   │   │   ├── onboarding/        splash, onboarding
│   │   │   ├── auth/              session, accueil, mode local
│   │   │   ├── dashboard/
│   │   │   ├── transactions/      domaine, repository, formulaire, historique
│   │   │   ├── categories/
│   │   │   ├── budgets/           domaine, repository, alertes, écran
│   │   │   ├── statistics/
│   │   │   └── settings/          profil, confidentialité, clés de préférences
│   │   ├── synchronization/       outbox (planner + writer), payloads, providers
│   │   └── main.dart · main_dev.dart · main_prod.dart
│   ├── test/                      unitaires, base de données, widgets
│   ├── integration_test/
│   └── drift_schemas/kolo/        drift_schema_vN.json (un fichier par version)
├── backend/
│   ├── kolo/                    settings.py (variables d'environnement), settings_test.py, urls.py
│   ├── apps/
│   │   ├── core/                SyncModel abstrait, format d'erreur, horodatages ms, journal sans données
│   │   ├── accounts/            User (e-mail, prénom, fuseau), JWT, mot de passe oublié par code
│   │   ├── categories/          Category + data migration 0002 des catégories par défaut
│   │   ├── transactions/  budgets/
│   │   └── sync/                SyncCounter, ProcessedOperation, validation, service push/pull,
│   │                            commande purge_sync_data
│   ├── tests/                   un fichier par domaine (auth, push, conflits, pull/purge…)
│   └── Dockerfile · docker-entrypoint.sh · requirements*.txt · pyproject.toml
├── deploy/native/               service systemd, vhost Nginx, scripts (installation, sauvegarde, purge)
├── docs/  .github/workflows/    (mobile.yml, backend.yml)
└── README.md
```

Les repositories sont rangés dans la couche `data` de chaque feature. Les écrans
ne dépendent que des providers (`app/providers.dart`, providers de feature) et
des entités du domaine.

## 5. Modèle de données

### 5.1 Champs communs synchronisables

Présents sur `transactions`, `categories`, `budgets` :

| Champ | Type SQLite | Rôle |
|---|---|---|
| `id` | TEXT (UUID v4) PK | généré par le client ; fixe pour les catégories par défaut |
| `user_id` | TEXT NULL | `NULL` en mode local et pour les catégories par défaut |
| `created_at`, `updated_at` | TEXT ISO-8601 UTC (ms) | horodatages techniques |
| `version` | INTEGER, défaut 0 | version serveur ; 0 = jamais confirmée |
| `server_updated_at` | TEXT NULL | horodatage serveur |
| `deleted_at` | TEXT NULL | tombstone |
| `sync_status` | TEXT | `localOnly` · `pending` · `synced` · `conflict` · `failed` — **client uniquement** |

### 5.2 Tables métier

**`transactions`** — `type` (`expense`/`income`), `amount` INTEGER
`CHECK (amount > 0 AND amount <= 999999999999)`, `currency` (défaut `XOF`),
`category_id` → `categories.id`, `note` ≤ 140, `note_search` (note normalisée
pour la recherche), `occurred_on` `YYYY-MM-DD`.
Index : `(user_id, occurred_on)`, `(user_id, category_id)`,
`(user_id, type, occurred_on)`, `(sync_status)`.

**`categories`** — `name` (1–40), `type`, `icon` (clé), `color` NULL,
`is_default`, `sort_order`. Index unique
`(COALESCE(user_id,''), type, lower(name)) WHERE deleted_at IS NULL`.

**`budgets`** — `period` `YYYY-MM`, `category_id` NULL (= global ; non nul réservé
à une version future), `limit_amount` ≥ 0, `currency`, `alert_thresholds` (JSON,
défaut `[80,100]`). Index unique
`(COALESCE(user_id,''), period, COALESCE(category_id,'')) WHERE deleted_at IS NULL`.

### 5.3 Tables techniques

**`outbox`** (§4.3)

| Champ | Rôle |
|---|---|
| `seq` INTEGER PK AUTOINCREMENT | ordre d'envoi strict |
| `op_id` TEXT UNIQUE | clé d'idempotence |
| `entity`, `entity_id`, `op_type` | cible et nature (`upsert`/`delete`) |
| `payload` | instantané JSON (clés de l'API) |
| `changed_fields` | JSON — champs modifiés depuis `base_version` (fusion par champ) |
| `base_version` | version serveur connue lors de la modification |
| `user_id` | compte propriétaire : jamais envoyé avec la session d'un autre |
| `status` | `pending` / `failed` |
| `attempts`, `next_attempt_at`, `last_error` | nouvelles tentatives (backoff) |
| `created_at` | horodatage |

**`sync_state`** — une ligne par compte : `cursor`, `last_success_at`,
`last_attempt_at`, `last_error`.

**`app_settings`** — clé/valeur : onboarding vu, mode de session, identifiant
d'installation, préférences, seuils d'alerte déjà notifiés. **Jamais de jeton.**

### 5.4 Devises

`core/constants/currencies.dart` : `{code: XOF, minorUnit: 0, symbol: F CFA}`.
Une devise à 2 décimales s'ajoute sans changer le schéma (montant toujours entier
dans la plus petite unité) ; `formatMoney` sait déjà l'afficher.

### 5.5 Catégories par défaut

Neuf catégories de dépenses et six de revenus, avec des **UUID fixes**
(`c0a7e9e0-0000-4000-8000-0000000000NN` pour les dépenses, `…0000000001NN` pour
les revenus), définis dans `core/constants/default_categories.dart` et recopiés à
l'identique dans la data migration Django. Elles sont insérées
(`INSERT OR IGNORE`) à chaque ouverture de la base.

## 6. Synchronisation (résumé)

Voir [SYNC.md](SYNC.md). Déjà en place (phase 2) : outbox transactionnelle,
compactage, payloads. À venir (phase 5) : moteur push/pull, résolution des
conflits, backoff, déclencheurs, passage du mode local à un compte.

## 7. Migrations

- `AppDatabase.schemaVersion` est la version courante (actuellement **1**).
- Procédure pour toute évolution du schéma :
  1. modifier les tables et incrémenter `schemaVersion` ;
  2. `dart run build_runner build` ;
  3. `dart run drift_dev make-migrations` — exporte
     `drift_schemas/kolo/drift_schema_vN.json`, génère
     `lib/database/app_database.steps.dart` et les tests
     `test/database/generated/` ;
  4. écrire l'étape dans `onUpgrade: stepByStep(...)` ;
  5. compléter le test de migration avec des données existantes (transactions
     **et** outbox) et vérifier qu'aucune ligne n'est perdue.
- `beforeOpen` active `PRAGMA foreign_keys = ON` et réinsère les catégories par
  défaut manquantes.

## 8. Tests

| Dossier | Contenu |
|---|---|
| `test/core/` | formatage XOF, saisie des montants, dates, normalisation |
| `test/features/` | validation, budget, alertes, repository des opérations (mode local et compte) |
| `test/synchronization/` | compactage de l'outbox |
| `test/database/` | contraintes, seeding, agrégats SQL, limites de mois, pagination, persistance après fermeture |
| `test/widgets/` | formulaire (validation, double appui, annulation), tableau de bord, historique |
| `test/app/` | règles de redirection du routeur |

Commandes : `dart analyze`, `flutter test`.

### Backend

| Fichier | Contenu |
|---|---|
| `tests/test_auth.py` | inscription, connexion, rotation et liste noire des jetons, profil, mots de passe |
| `tests/test_sync_push.py` | enveloppe, validation, idempotence, propriété, mises à jour et tombstones |
| `tests/test_sync_conflicts.py` | deux appareils : fusion par champ, conflits, suppression, restauration |
| `tests/test_sync_pull.py` | curseur, pagination, ordre, catégorie jointe, purge et `410` |
| `tests/test_default_categories.py` | catégories par défaut identiques à `default_categories.dart` |
| `tests/test_api_basics.py` | santé, erreurs JSON, **aucun montant, note ni identifiant dans les journaux** |

Commandes : `ruff check .`, `ruff format --check .`, `pytest`.

## Décisions

Exigences ambiguës ou contraintes rencontrées, et choix retenu (§14.10).

| # | Sujet | Décision | Raison |
|---|---|---|---|
| D1 | Android minSdk | **24** au lieu de 23 | Flutter 3.47 impose API 24 minimum. Android 6 est marginal dans le parc visé. |
| D2 | iOS minimum | **15.0** | Valeur imposée par le gabarit Flutter actuel ; couvre la cible « 14+ » à une version près. |
| D3 | Génération Riverpod | Providers écrits à la main (pas de `riverpod_generator`) | Moins de génération de code sur des machines de dev modestes ; API identique. Le générateur reste disponible. |
| D4 | Freezed | Entités du domaine écrites à la main ; Freezed + json_serializable réservés aux DTO réseau (phase 5) | Peu d'entités, sans union ; évite un passage de build_runner à chaque modification. |
| D5 | Fuseau horaire | « Aujourd'hui » = date locale de l'appareil. `occurred_on` est une date sans heure : les totaux mensuels comparent des chaînes `YYYY-MM-DD`, sans conversion. Le fuseau du profil (`Africa/Porto-Novo`) sera stocké côté serveur. | Robuste hors ligne ; UTC+1 sans heure d'été au Bénin. |
| D6 | Date future | Autorisée jusqu'à J+1 ; **refusée** au-delà avec un message clair. | « autorisée seulement jusqu'à J+1 » ; une date lointaine est presque toujours une erreur de saisie. |
| D7 | Outbox en mode local | Aucune entrée d'outbox sans compte (`sync_status = localOnly`). L'outbox est créée au rattachement à un compte (phase 5). | Rien à envoyer ; évite un journal qui grossit sans fin. |
| D8 | Compactage | Fusion seulement si l'entrée en attente n'a **jamais été tentée** (`attempts = 0`) ; création puis suppression avant envoi = annulation. Nouvel `op_id` pour tout contenu nouveau. | Une entrée tentée a peut-être été appliquée (réponse perdue) : la modifier casserait l'idempotence. |
| D9 | Fusion par champ | L'outbox transporte `changed_fields` ; le serveur détecte le conflit champ par champ. | Le serveur sait ce que le client a réellement modifié, sans deviner. |
| D10 | Recherche | Colonne `note_search` normalisée (minuscules, sans accents) écrite par le repository. | SQLite n'a pas de comparaison insensible aux accents. |
| D11 | Horodatages | Texte ISO-8601 UTC tronqué à la milliseconde. | Format fixe : l'ordre des chaînes est l'ordre chronologique (pagination par curseur). |
| D12 | Budget | Le plafond saisi s'applique au mois courant et aux suivants (reconduction = budget le plus récent ≤ mois). Seuils proposés : 50/70/80/90/100 %. | « reconduit automatiquement tant que l'utilisateur ne le modifie pas » sans créer une ligne par mois. |
| D13 | Alertes | Seuil mémorisé **avant** l'affichage de la notification ; une seule notification (seuil le plus haut) si plusieurs sont franchis d'un coup. | Préférer une alerte manquée à une alerte répétée à chaque saisie. |
| D14 | Graphiques | `fl_chart` reçoit des `double` pour le rendu seulement ; montants et % affichés sont calculés en entiers. | Contrainte de la bibliothèque, sans impact sur l'exactitude. |
| D15 | Logo | Logo KOLO fourni par le produit (`assets/images/kolo_logo.png`) ; « By ASITECH SOLUTION » en texte simple. | Remplace le wordmark provisoire ; aucun logo ASITECH inventé. |
| D16 | Icônes | Material Icons « Rounded » intégrées à Flutter, un seul jeu. | Aucune dépendance ni téléchargement supplémentaire. |
| D17 | Chiffrement local | v1 : sandbox de l'OS. `database/connection.dart` est le point unique où brancher SQLCipher (`sqlcipher_flutter_libs`), clé dans le stockage sécurisé. | Conforme au §8 ; migration future localisée. |
| D18 | Sauvegarde Android | `allowBackup=false` + règles d'exclusion totales. Conséquence assumée : en mode local, rien n'est restauré sur un nouveau téléphone (l'écran d'explication le dit). | Exigence §8. |
| D19 | Snackbar « Annuler » | `persist: false` explicite. | Depuis Flutter 3.29, une snackbar avec action ne se ferme plus seule ; la spécification impose 5 s. |
| D20 | Écran d'accueil | Tant que le backend n'existe pas, seul « Commencer sans compte » est proposé. | « Aucun bouton sans action » (§14.4). |
| D21 | Date future côté serveur | Refusée au-delà de J+1 **dans le fuseau le plus en avance (UTC+14)** ; avant 2000-01-01 refusée. | Le serveur ne doit jamais rejeter une saisie que le téléphone a acceptée hors ligne, quel que soit son fuseau ; les fautes de frappe grossières restent bloquées. |
| D22 | Mot de passe oublié | Code à 6 chiffres par e-mail (15 min, 5 essais, usage unique, seule une empreinte HMAC est stockée) plutôt qu'un lien. | Pas de liens profonds en v1 ; un code se saisit dans l'application. |
| D23 | Idempotence | Seules les opérations `applied` sont mémorisées ; `duplicate` renvoie le résultat de la première application. | Conflits et rejets ne modifient rien. Renvoyer la version d'origine évite qu'un téléphone se croie à jour avec des données plus anciennes. |
| D24 | Restauration | Un `upsert` sur un tombstone est une restauration s'il porte `base_version` = version du tombstone ; sinon conflit. | « La suppression l'emporte, sauf restauration explicite » sans champ supplémentaire dans le protocole. |
| D25 | Instantané à jour | Avec `base_version` = version serveur, l'instantané complet est appliqué ; avec une base ancienne, seuls les `changed_fields`. | Le client connaît alors exactement l'état du serveur ; la fusion par champ n'est utile qu'en cas de concurrence. |
| D26 | `change_seq` | Compteur par compte verrouillé pendant le push (pas de séquence globale). | Garantit qu'un curseur ne saute jamais un changement en cours de validation ; la contention reste limitée à un compte. |
| D27 | Purge | Tombstones et opérations traitées effacés après 90 jours ; `purged_seq` → `410 cursor_reset_required`. | PRIVACY.md ; un téléphone resté hors ligne longtemps ne peut pas manquer une suppression sans le savoir. |
| D28 | Catégories par défaut | Partagées (`user` nul), en lecture seule, jamais renvoyées par le pull. | Mêmes UUID sur tous les appareils (§5.5) ; rien à synchroniser. |
| D29 | Base des tests backend | SQLite en local, PostgreSQL 16 en CI. | La machine de développement n'a ni PostgreSQL ni Docker ; les contraintes (index partiels, unicité sur `lower(name)`) existent sur les deux. |
