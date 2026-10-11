import 'package:drift/drift.dart';

import '../core/constants/default_categories.dart';
import '../core/model/enums.dart';
import 'app_database.steps.dart';
import 'daos/budgets_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/sync_conflicts_dao.dart';
import 'daos/sync_state_dao.dart';
import 'daos/transactions_dao.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/outbox_table.dart';
import 'tables/sync_conflicts_table.dart';
import 'tables/technical_tables.dart';
import 'tables/transactions_table.dart';

export 'daos/budgets_dao.dart';
export 'daos/categories_dao.dart';
export 'daos/outbox_dao.dart';
export 'daos/settings_dao.dart';
export 'daos/sync_conflicts_dao.dart';
export 'daos/sync_state_dao.dart';
export 'daos/transactions_dao.dart';

part 'app_database.g.dart';

/// Base locale — **source de vérité pour l'interface** (§4.1).
///
/// L'ouverture concrète (fichier sur l'appareil, mémoire en test) est
/// injectée par [QueryExecutor] : voir `database/connection.dart`.
@DriftDatabase(
  tables: [
    Categories,
    Transactions,
    Budgets,
    Outbox,
    SyncState,
    SyncConflicts,
    AppSettings,
  ],
  daos: [
    TransactionsDao,
    CategoriesDao,
    BudgetsDao,
    OutboxDao,
    SettingsDao,
    SyncStateDao,
    SyncConflictsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Incrémenter à chaque changement de schéma, puis exécuter
  /// `dart run drift_dev make-migrations` (voir docs/ARCHITECTURE.md).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    // Étapes générées par `dart run drift_dev make-migrations` (voir
    // docs/ARCHITECTURE.md §7). Chaque étape est couverte par un test de
    // migration — `test/database/generated/kolo/migration_test.dart` (schéma)
    // et `test/database/migration_v2_test.dart` (données conservées).
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.syncConflicts);
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Idempotent : garantit la présence des catégories par défaut après
      // une création comme après une migration.
      await seedDefaultCategories();
    },
  );

  Future<void> seedDefaultCategories() async {
    await batch((b) {
      b.insertAll(categories, [
        for (final c in DefaultCategories.all)
          CategoriesCompanion.insert(
            id: c.id,
            name: c.name,
            type: c.type,
            icon: c.icon,
            isDefault: const Value(true),
            sortOrder: Value(c.sortOrder),
            createdAt: DefaultCategories.createdAt,
            updatedAt: DefaultCategories.createdAt,
            syncStatus: SyncStatus.synced,
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }
}

/// Filtre « appartient au propriétaire courant » : `user_id IS NULL` en mode
/// local, `user_id = ?` pour un compte.
Expression<bool> ownedBy(GeneratedColumn<String> column, String? userId) =>
    userId == null ? column.isNull() : column.equals(userId);
