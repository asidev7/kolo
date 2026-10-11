import 'dart:ui';

import 'package:workmanager/workmanager.dart';

import '../../app/app_config.dart';
import '../../app/sync.dart';
import '../../database/app_database.dart';
import '../../database/connection.dart';
import '../engine/sync_engine.dart';

/// Tâche de fond : vider l'outbox sans que l'application soit ouverte.
///
/// WorkManager (Android) / BGTaskScheduler (iOS) réveillent l'application au
/// mieux toutes les 15 minutes, quand le réseau est là. Ce n'est **pas** le
/// chemin principal — la synchronisation normale part de l'écriture locale —
/// mais c'est le filet de sécurité pour un téléphone resté longtemps hors
/// ligne : les opérations finissent par partir sans que l'utilisateur rouvre
/// l'application.
///
/// Ce fichier est une **racine de composition** au même titre que
/// `app/sync.dart` : l'isolate de fond n'a ni conteneur Riverpod, ni
/// utilisateur connecté à l'écran. Il rebâtit donc la pile à partir de la base
/// et du stockage sécurisé.

/// Nom de la tâche périodique, unique et stable.
const String kSyncTaskName = 'kolo.background.sync';

/// Point d'entrée enregistré auprès de WorkManager.
///
/// Doit rester une fonction **de premier niveau** annotée
/// `@pragma('vm:entry-point')` : elle est appelée dans un isolate créé par le
/// système, sans passer par `main()`.
@pragma('vm:entry-point')
void koloSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // iOS déclenche aussi un « background fetch » global : on l'accepte au
    // même titre que notre tâche périodique.
    if (taskName != kSyncTaskName &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }
    return runBackgroundSync();
  });
}

/// Corps du cycle, sans dépendance au plugin.
///
/// Séparé du dispatcher pour être appelable depuis un test : c'est le seul
/// moyen de vérifier quelque chose d'une tâche que WorkManager seul sait
/// déclencher.
Future<bool> runBackgroundSync({AppDatabase? existingDatabase}) async {
  // Les plugins (chemin de la base, stockage sécurisé) doivent être
  // enregistrés dans cet isolate : `flutter_secure_storage` et `path_provider`
  // passent par des canaux de plateforme.
  DartPluginRegistrant.ensureInitialized();

  final database = existingDatabase ?? AppDatabase(openKoloDatabase());
  try {
    final config = AppConfig.fromEnvironment(Flavor.dev);
    // Sans API configurée, l'application est en mode local : rien à envoyer.
    if (!config.hasBackend) return true;

    final stack = buildBackgroundSyncStack(database, config);
    final report = await stack.engine.syncNow();
    // Une panne réseau n'est pas un échec de la tâche : la prochaine
    // occurrence périodique réessaiera, sans recul imposé par WorkManager.
    return report.result != SyncResult.failed;
  } catch (_) {
    // Ne jamais laisser une exception sortir : la tâche périodique suivante
    // doit pouvoir se relancer normalement.
    return true;
  } finally {
    if (existingDatabase == null) await database.close();
  }
}
