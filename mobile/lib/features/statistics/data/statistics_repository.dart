import 'package:meta/meta.dart';

import '../../../core/model/enums.dart';
import '../../../core/utils/local_date.dart';
import '../../../database/app_database.dart';
import '../../transactions/domain/finance.dart';

/// Part d'une catégorie dans les dépenses d'une période.
@immutable
class CategoryShare {
  const CategoryShare({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.total,
    required this.percent,
  });

  final String categoryId;
  final String name;
  final String icon;
  final int total;

  /// Pourcentage entier arrondi à l'unité inférieure.
  final int percent;
}

/// Revenus et dépenses d'un mois.
@immutable
class MonthlyPoint {
  const MonthlyPoint(this.month, this.totals);

  final YearMonth month;
  final TypeTotals totals;
}

/// Lectures statistiques : uniquement des requêtes SQL agrégées, jamais de
/// chargement de toutes les opérations en mémoire (§3.H).
class StatisticsRepository {
  StatisticsRepository(this._db);

  final AppDatabase _db;

  Stream<List<CategoryShare>> watchExpenseShares(
    String? ownerId,
    YearMonth month,
  ) => _db.transactionsDao
      .watchTotalsByCategory(
        ownerId,
        TransactionType.expense,
        month.firstDay,
        month.lastDay,
      )
      .map((rows) {
        final sum = rows.fold<int>(0, (acc, r) => acc + r.total);
        return [
          for (final r in rows)
            CategoryShare(
              categoryId: r.categoryId,
              name: r.name,
              icon: r.icon,
              total: r.total,
              percent: Finance.percentOf(r.total, sum) ?? 0,
            ),
        ];
      });

  /// Les [count] mois se terminant par [last], du plus ancien au plus récent,
  /// mois vides compris.
  Stream<List<MonthlyPoint>> watchMonthly(
    String? ownerId,
    YearMonth last, {
    int count = 6,
  }) {
    final first = last.addMonths(-(count - 1));
    return _db.transactionsDao
        .watchMonthlyTotals(ownerId, first, last)
        .map(
          (byMonth) => [
            for (var i = 0; i < count; i++)
              MonthlyPoint(
                first.addMonths(i),
                byMonth[first.addMonths(i).toIso()] ?? TypeTotals.zero,
              ),
          ],
        );
  }

  /// Dépenses cumulées jour après jour sur le mois (index 0 = jour 1).
  Stream<List<int>> watchCumulativeExpenses(String? ownerId, YearMonth month) =>
      _db.transactionsDao
          .watchDailyExpenses(ownerId, month.firstDay, month.lastDay)
          .map(
            (byDate) => Finance.cumulative({
              for (final e in byDate.entries)
                LocalDate.parse(e.key).day: e.value,
            }, month.dayCount),
          );
}
