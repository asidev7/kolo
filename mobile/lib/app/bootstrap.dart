import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../core/providers/core_providers.dart';
import '../database/app_database.dart';
import '../database/connection.dart';
import '../synchronization/background/background_scheduler.dart';
import 'app.dart';
import 'app_config.dart';
import 'sync.dart';

/// Démarrage commun à tous les flavors.
///
/// Rien de bloquant ni de réseau ici : la base s'ouvre paresseusement à la
/// première requête, déclenchée par l'écran de démarrage (§3.A).
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');

  final config = AppConfig.fromEnvironment(flavor);
  if (flavor == Flavor.prod && !config.hasBackend && kReleaseMode) {
    // Une build prod sans API reste utilisable en mode local ; on le
    // signale seulement dans les journaux.
    debugPrint('API_BASE_URL absent : mode local uniquement.');
  }

  final database = AppDatabase(openKoloDatabase());

  // Tâche périodique de synchronisation : jamais bloquante, et sans objet
  // quand aucune API n'est configurée (mode local).
  if (config.hasBackend) {
    unawaited(
      WorkManagerScheduler().register()
      // Un échec d'enregistrement (plateforme, permissions) privé
      // seulement de la tâche de fond : le reste fonctionne.
      .catchError((Object _) {}),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        appConfigProvider.overrideWithValue(config),
        // Remplace le déclencheur inerte par le coordonnateur réel (§4.2).
        localWriteSyncOverride(),
      ],
      child: const KoloApp(),
    ),
  );
}
