# KOLO

**Ton argent. Tes décisions. Ton avenir.**
Application mobile de finances personnelles offline-first — développée par
ASITECH SOLUTION.

KOLO permet d'enregistrer revenus et dépenses **sans connexion**, de suivre un
solde net enregistré, un budget mensuel et des statistiques. KOLO n'est pas une
banque et ne connaît pas le solde réel d'un compte bancaire ou Mobile Money.

## État d'avancement

| Phase | Contenu | État |
|---|---|---|
| 1 | Socle Flutter, design system, navigation, base Drift, démarrage, onboarding | ✅ |
| 2 | Catégories par défaut, opérations (domaine, base, formulaire), calculs, outbox | ✅ |
| 3 | Tableau de bord, historique, budget et alertes, statistiques | ✅ |
| 4 | Backend Django REST Framework : comptes, JWT, synchronisation push/pull, purge, déploiement | ✅ |
| 5 | Moteur de synchronisation, comptes | à venir |
| 6 | Sécurité, export CSV, performances, accessibilité | à venir |
| 7 | Bêta privée | à venir |

## Dépôt

```
mobile/    application Flutter (Android, iOS)
backend/   API Django REST Framework
deploy/    déploiement (scripts, service systemd, vhost Nginx, sauvegardes)
docs/      architecture, synchronisation, confidentialité, limites connues
```

Documentation : [Architecture](docs/ARCHITECTURE.md) · [API](docs/API.md) ·
[Synchronisation](docs/SYNC.md) · [Confidentialité](docs/PRIVACY.md) ·
[Limites connues](docs/KNOWN_LIMITATIONS.md)

## Application mobile

### Prérequis

- Flutter stable ≥ 3.47 (Dart ≥ 3.13)
- Android : SDK 36, JDK 17 ; appareil ou émulateur Android 7.0+
- iOS : Xcode récent, iOS 15+

### Installation et lancement

```bash
cd mobile
flutter pub get
flutter run -t lib/main_dev.dart
```

Le code généré (Drift) est versionné. Après une modification des tables ou des
DAO :

```bash
dart run build_runner build
```

Pour un changement de schéma, suivre la procédure de
[ARCHITECTURE.md §7](docs/ARCHITECTURE.md#7-migrations).

### Flavors et configuration

| Point d'entrée | Usage |
|---|---|
| `lib/main_dev.dart` | développement |
| `lib/main_prod.dart` | production |

L'URL de l'API n'est jamais codée en dur :

```bash
flutter run -t lib/main_dev.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter build apk -t lib/main_prod.dart --split-per-abi \
  --dart-define=API_BASE_URL=https://api.example.com
```

Sans `API_BASE_URL`, l'application fonctionne en mode local uniquement.

### Qualité et tests

```bash
cd mobile
dart format --set-exit-if-changed lib test
dart analyze
flutter test
```

Les tests utilisent une vraie base SQLite en mémoire ; aucune donnée fictive
n'est présente dans l'application.

## Backend

### Prérequis

- Python 3.12
- PostgreSQL 16 en production (SQLite suffit pour développer et tester)

### Installation et lancement

```bash
cd backend
python -m venv .venv
.venv/bin/pip install -r requirements-dev.txt        # Windows : .venv\Scripts\pip
DJANGO_DEBUG=1 .venv/bin/python manage.py migrate
DJANGO_DEBUG=1 .venv/bin/python manage.py runserver 0.0.0.0:8000
```

Avec `DJANGO_DEBUG=1` et sans `DATABASE_URL`, l'API utilise `backend/db.sqlite3`
et affiche les e-mails dans la console. Depuis l'émulateur Android :
`--dart-define=API_BASE_URL=http://10.0.2.2:8000`.

Hors développement, `DJANGO_SECRET_KEY` et `DATABASE_URL` sont obligatoires : en
production ils proviennent du fichier d'environnement du service
(voir [deploy/native/README.md](deploy/native/README.md)).

### Qualité et tests

```bash
cd backend
ruff check . && ruff format --check .
pytest                                              # SQLite en mémoire
DATABASE_URL=postgres://kolo:kolo@localhost:5432/kolo pytest   # PostgreSQL
```

### Production

Déploiement natif (venv Python, gunicorn, systemd, Nginx de l'hôte) : voir
[deploy/native/README.md](deploy/native/README.md).

### Machine de développement modeste

`android/gradle.properties` limite Gradle à 2 Go de heap. Une valeur plus élevée
sur une machine à 8 Go de RAM provoque des crashs JVM (`hs_err_pid*.log`).
