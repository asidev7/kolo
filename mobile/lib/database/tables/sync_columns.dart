import 'package:drift/drift.dart';

import '../../core/model/enums.dart';

/// Champs communs à toutes les entités synchronisables (§5.2).
mixin SyncColumns on Table {
  /// UUID v4 généré par le client (ou fixe pour les catégories par défaut).
  TextColumn get id => text()();

  /// `null` en mode local et pour les catégories par défaut.
  TextColumn get userId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  /// Version serveur ; 0 tant que l'enregistrement n'a jamais été confirmé.
  IntColumn get version => integer().withDefault(const Constant(0))();

  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();

  /// Tombstone : un enregistrement supprimé n'est jamais effacé
  /// physiquement avant confirmation serveur (§4.2).
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus => textEnum<SyncStatus>()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
