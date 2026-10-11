import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/technical_tables.dart';

part 'settings_dao.g.dart';

/// Accès clé/valeur aux préférences locales.
@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Future<String?> read(String key) => (select(
    appSettings,
  )..where((s) => s.key.equals(key))).map((s) => s.value).getSingleOrNull();

  Stream<String?> watch(String key) => (select(
    appSettings,
  )..where((s) => s.key.equals(key))).map((s) => s.value).watchSingleOrNull();

  Future<void> write(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  Future<void> remove(String key) =>
      (delete(appSettings)..where((s) => s.key.equals(key))).go();
}
