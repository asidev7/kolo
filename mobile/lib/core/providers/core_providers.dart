import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_config.dart';
import '../../database/app_database.dart';
import '../utils/time_source.dart';

/// Base locale. Toujours surchargée au démarrage (`bootstrap`) ou dans les
/// tests : il n'existe qu'une seule connexion par processus.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider doit être surchargé'),
);

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(Flavor.dev),
);

final timeSourceProvider = Provider<TimeSource>((ref) => const TimeSource());

final idGeneratorProvider = Provider<IdGenerator>((ref) => generateUuidV4);
