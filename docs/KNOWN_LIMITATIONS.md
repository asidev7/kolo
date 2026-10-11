# Limites connues

Mis à jour à chaque fin de phase. État : **fin de la phase 4** (application
complète en mode local ; API serveur prête, pas encore branchée à
l'application).

## Fonctionnelles

| Limite | Prévu en |
|---|---|
| L'API des comptes existe (inscription, connexion, mot de passe oublié) mais l'application ne propose encore que le mode local | Phase 5 |
| Pas de synchronisation ni de sauvegarde serveur ; la perte du téléphone entraîne la perte des données (écrit à l'écran) | Phase 5 |
| Écran « Conflits à résoudre », état de synchronisation dans le Profil | Phase 5 |
| Export CSV | Phase 6 |
| Suppression de compte (application **et** API) | Phase 6 |
| Deux téléphones qui créent hors ligne le budget du même mois : le second est rejeté (`duplicate_budget`) ; le client devra adopter celui du serveur | Phase 5 |
| Une seule devise (XOF) ; budgets par catégorie : modèle prêt, pas d'interface | Hors v1 |
| Catégories personnalisées : création et archivage seulement (pas de renommage, fusion ni réorganisation) | Hors v1 |
| Le budget se modifie pour le mois courant uniquement (il est reconduit aux mois suivants) | — |

## Techniques

| Limite | Détail |
|---|---|
| Android 7.0 minimum (API 24) | Imposé par le SDK Flutter utilisé ; la spécification visait API 23 (voir ARCHITECTURE.md, D1). |
| iOS 15 minimum | Gabarit Flutter actuel (D2). |
| Base locale non chiffrée | Protégée par le sandbox de l'OS ; SQLCipher prévu derrière `database/connection.dart` (D17). |
| Pas de sauvegarde Android automatique | Volontaire (§8) ; en mode local, un changement de téléphone perd les données. |
| Tests de migration Drift | Le schéma v1 est exporté (`drift_schemas/kolo/drift_schema_v1.json`) ; les tests de montée de version seront générés dès la v2. |
| Tests d'intégration sur appareil (`integration_test/`) | Arrivent avec la synchronisation (phase 5) ; les parcours locaux sont couverts par des tests de widgets sur base SQLite réelle en mémoire. |
| Build APK non encore validée | Sur la machine de développement actuelle (8 Go de RAM, ~1 Go libre), la VM Dart ne peut plus créer de threads pendant la build Gradle (« Could not start thread … 22 »). Code Dart, analyse et tests ne sont pas en cause. À valider sur une machine plus dotée ou en CI. |
| Taille de l'APK | Non mesurée en release ; le logo (500 Ko) peut être optimisé. |

## Backend

| Limite | Détail |
|---|---|
| Tests sur PostgreSQL uniquement en CI | Ni PostgreSQL ni Docker sur la machine de développement : les tests locaux tournent sur SQLite, la CI GitHub les rejoue sur PostgreSQL 16 (D29). |
| Image Docker non construite localement | Construite par la CI (`backend.yml`, job `docker`). Le déploiement Compose n'a pas encore été essayé sur un serveur. |
| Limitation de débit applicative par processus | Le cache des throttles DRF est local à chaque worker Gunicorn ; Nginx (`limit_req`) applique la limite réelle par adresse IP. Un cache partagé (Redis) sera utile au-delà d'un serveur. |
| Jeton d'accès valable jusqu'à expiration | Après déconnexion ou changement de mot de passe, un access token déjà émis reste valable au plus 15 minutes (les refresh tokens, eux, sont révoqués immédiatement). |
| Envoi d'e-mail synchrone | Le code de mot de passe oublié est envoyé pendant la requête ; une file de tâches n'est pas justifiée au volume de la bêta. |
| Opérations traitées conservées 90 jours | Une opération tentée, dont la réponse s'est perdue, puis renvoyée plus de 90 jours après serait appliquée une seconde fois. |
| Coordonnées de l'éditeur | E-mail d'expéditeur, domaine et contact de la politique de confidentialité à fournir par ASITECH SOLUTION (aucune valeur inventée). |

## Améliorations envisagées

- Verrouillage par code PIN ou biométrie (modèle prévu, hors MVP).
- Mode sombre (tous les styles passent déjà par le `ThemeData`).
- Opérations récurrentes, import de relevés, Mobile Money (hors v1).
