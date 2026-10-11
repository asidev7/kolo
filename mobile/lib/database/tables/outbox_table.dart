import 'package:drift/drift.dart';

import '../../core/model/enums.dart';

/// Journal des opérations à envoyer au serveur (§4.3).
///
/// Écrit dans la **même transaction SQLite** que l'enregistrement métier :
/// une opération validée localement ne peut pas exister sans son entrée
/// d'outbox, et inversement.
@DataClassName('OutboxEntry')
@TableIndex(name: 'outbox_owner_order', columns: {#userId, #status, #seq})
@TableIndex(name: 'outbox_entity', columns: {#entityId})
class Outbox extends Table {
  /// Ordre d'envoi strict (plus fiable qu'un horodatage à égalité).
  IntColumn get seq => integer().autoIncrement()();

  /// Clé d'idempotence côté serveur.
  TextColumn get opId => text().unique()();

  TextColumn get entity => textEnum<SyncEntity>()();

  TextColumn get entityId => text()();

  TextColumn get opType => textEnum<OutboxOpType>()();

  /// Instantané JSON de l'enregistrement au moment de l'opération.
  TextColumn get payload => text()();

  /// Liste JSON des champs modifiés depuis `base_version` ; permet la fusion
  /// champ par champ côté serveur (§4.5).
  TextColumn get changedFields => text().withDefault(const Constant('[]'))();

  IntColumn get baseVersion => integer()();

  /// Compte propriétaire : on n'envoie jamais l'opération d'un compte avec
  /// la session d'un autre.
  TextColumn get userId => text()();

  TextColumn get status =>
      textEnum<OutboxStatus>().withDefault(const Constant('pending'))();

  /// Incrémenté **avant** l'envoi : une entrée déjà tentée n'est plus
  /// compactée (elle a peut-être été appliquée côté serveur).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Code d'erreur technique, jamais de montant ni de note.
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}
