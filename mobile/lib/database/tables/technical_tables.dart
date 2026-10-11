import 'package:drift/drift.dart';

/// Curseur et état de synchronisation, par compte (§5.7).
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get userId => text()();

  /// Curseur opaque renvoyé par `sync/pull`.
  TextColumn get cursor => text().nullable()();

  DateTimeColumn get lastSuccessAt => dateTime().nullable()();

  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// Préférences et drapeaux locaux sous forme clé/valeur (§5.7).
///
/// Jamais de jeton ni de secret ici : ils vont dans le stockage sécurisé.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
