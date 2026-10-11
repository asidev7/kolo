import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Ouvre la base de l'appareil (`kolo.sqlite` dans le dossier privé de
/// l'application, protégé par le sandbox de l'OS — §8).
///
/// `shareAcrossIsolates` : la tâche de synchronisation en arrière-plan
/// (phase 5) passe par la même instance que l'interface, ce qui sérialise
/// les écritures et garde les streams cohérents.
///
/// Évolution prévue : chiffrement SQLCipher derrière cette fonction, clé dans
/// le stockage sécurisé (voir docs/ARCHITECTURE.md, Décisions).
///
/// Web (aperçu de développement uniquement) : SQLite compilé en WebAssembly,
/// fichiers `web/sqlite3.wasm` et `web/drift_worker.js` dont les versions
/// doivent suivre celles de `sqlite3` et `drift` dans `pubspec.lock`.
QueryExecutor openKoloDatabase() => driftDatabase(
  name: 'kolo',
  native: const DriftNativeOptions(shareAcrossIsolates: true),
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);
