import 'package:drift/drift.dart';

import '../../core/model/enums.dart';
import 'categories_table.dart';
import 'sync_columns.dart';

/// Opérations de l'utilisateur (§5.3).
///
/// Les montants sont des entiers : 1 unité = 1 franc CFA (§5.1).
@DataClassName('TransactionRow')
@TableIndex(name: 'tx_owner_date', columns: {#userId, #occurredOn})
@TableIndex(name: 'tx_owner_category', columns: {#userId, #categoryId})
@TableIndex(name: 'tx_owner_type_date', columns: {#userId, #type, #occurredOn})
@TableIndex(name: 'tx_sync_status', columns: {#syncStatus})
class Transactions extends Table with SyncColumns {
  TextColumn get type => textEnum<TransactionType>()();

  // Idiome Drift : la contrainte CHECK référence la colonne elle-même.
  // ignore: recursive_getters
  IntColumn get amount => integer().check(
    // ignore: recursive_getters
    amount.isBiggerThanValue(0) & amount.isSmallerOrEqualValue(999999999999),
  )();

  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('XOF'))();

  TextColumn get categoryId => text().references(Categories, #id)();

  TextColumn get note => text().nullable().withLength(max: 140)();

  /// Note normalisée (minuscules, sans accents) pour la recherche : SQLite
  /// n'offre pas de comparaison insensible aux accents.
  TextColumn get noteSearch => text().nullable()();

  /// Date métier `YYYY-MM-DD`, sans heure ni fuseau : l'ordre
  /// lexicographique est l'ordre chronologique.
  TextColumn get occurredOn => text().withLength(min: 10, max: 10)();
}
