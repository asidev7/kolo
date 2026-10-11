import 'dart:convert';

import '../../database/app_database.dart';

/// Instantanés envoyés dans `sync/push` (champ `data`, §4.4).
///
/// Clés en `snake_case`, identiques à celles de l'API. Aucun champ technique
/// local (`sync_status`, `note_search`) n'en fait partie.
abstract final class Payloads {
  static Map<String, Object?> transaction(TransactionRow row) => {
    'type': row.type.wire,
    'amount': row.amount,
    'currency': row.currency,
    'category_id': row.categoryId,
    'note': row.note,
    'occurred_on': row.occurredOn,
  };

  static Map<String, Object?> category(CategoryRow row) => {
    'name': row.name,
    'type': row.type.wire,
    'icon': row.icon,
    'color': row.color,
    'sort_order': row.sortOrder,
  };

  static Map<String, Object?> budget(BudgetRow row) => {
    'period': row.period,
    'category_id': row.categoryId,
    'limit_amount': row.limitAmount,
    'currency': row.currency,
    'alert_thresholds': jsonDecode(row.alertThresholds),
  };
}
