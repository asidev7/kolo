import 'package:drift/drift.dart';

import 'categories_table.dart';
import 'sync_columns.dart';

/// Plafond mensuel (§5.5). `category_id = null` désigne le budget global ;
/// une valeur non nulle est réservée aux budgets par catégorie (hors v1).
@DataClassName('BudgetRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX budgets_owner_period_category '
  "ON budgets (COALESCE(user_id, ''), period, COALESCE(category_id, '')) "
  'WHERE deleted_at IS NULL',
)
class Budgets extends Table with SyncColumns {
  /// Mois au format `YYYY-MM`.
  TextColumn get period => text().withLength(min: 7, max: 7)();

  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  // Idiome Drift : la contrainte CHECK référence la colonne elle-même.
  // ignore: recursive_getters
  IntColumn get limitAmount =>
      // ignore: recursive_getters
      integer().check(limitAmount.isBiggerOrEqualValue(0))();

  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('XOF'))();

  /// Liste JSON d'entiers, par ex. `[80,100]`.
  TextColumn get alertThresholds =>
      text().withDefault(const Constant('[80,100]'))();
}
