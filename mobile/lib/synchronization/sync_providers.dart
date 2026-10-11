import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import 'outbox/outbox_writer.dart';

final outboxWriterProvider = Provider<OutboxWriter>(
  (ref) => OutboxWriter(
    ref.watch(databaseProvider),
    ref.watch(timeSourceProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// Appelé après chaque écriture locale validée (§4.2, étape 5).
///
/// En mode local il n'y a rien à envoyer. Le moteur de synchronisation
/// (phase 5) remplace cette fonction par un déclenchement avec debounce de
/// 2 s ; l'écriture locale n'attend jamais le réseau.
final localWriteSignalProvider = Provider<void Function()>((ref) => () {});
