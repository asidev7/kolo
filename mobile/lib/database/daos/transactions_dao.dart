import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../core/model/enums.dart';
import '../../core/utils/local_date.dart';
import '../../core/utils/text_normalize.dart';
import '../app_database.dart';
import '../tables/categories_table.dart';
import '../tables/transactions_table.dart';

export '../../core/model/totals.dart';

part 'transactions_dao.g.dart';

/// Critères de lecture de l'historique (§3.F). Toujours limité à un
/// propriétaire et aux transactions non supprimées.
@immutable
class TransactionQuery {
  const TransactionQuery({
    required this.userId,
    this.type,
    this.from,
    this.to,
    this.categoryIds = const {},
    this.search,
  });

  final String? userId;
  final TransactionType? type;
  final LocalDate? from;
  final LocalDate? to;
  final Set<String> categoryIds;
  final String? search;
}

/// Position dans l'historique trié par `(occurred_on, created_at, id)`
/// décroissants — clé de pagination stable même à égalité de date.
@immutable
class HistoryCursor {
  const HistoryCursor(this.occurredOn, this.createdAt, this.id);

  factory HistoryCursor.of(TransactionRow row) =>
      HistoryCursor(row.occurredOn, row.createdAt, row.id);

  final String occurredOn;
  final DateTime createdAt;
  final String id;
}

@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.total,
  });

  final String categoryId;
  final String name;
  final String icon;
  final int total;
}

@DriftAccessor(tables: [Transactions, Categories])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.attachedDatabase);

  Future<TransactionRow?> findById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<TransactionRow?> watchById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Les `limit` dernières opérations (tableau de bord).
  Stream<List<TransactionRow>> watchRecent(String? userId, {int limit = 5}) =>
      (select(transactions)
            ..where((t) => _alive(t, userId))
            ..orderBy(_historyOrder)
            ..limit(limit))
          .watch();

  /// Page suivante après [after] (pagination par curseur, §3.F).
  Future<List<TransactionRow>> pageAfter(
    TransactionQuery query, {
    HistoryCursor? after,
    int limit = 50,
  }) {
    final stmt = select(transactions)
      ..where((t) => _matches(t, query))
      ..orderBy(_historyOrder)
      ..limit(limit);
    if (after != null) stmt.where((t) => _after(t, after));
    return stmt.get();
  }

  /// Toutes les opérations depuis le début jusqu'à [until] inclus (toutes si
  /// `null`) : permet de recharger les pages déjà affichées quand la table
  /// change, sans décalage ni doublon.
  Stream<List<TransactionRow>> watchUntil(
    TransactionQuery query,
    HistoryCursor? until,
  ) {
    final stmt = select(transactions)
      ..where(
        (t) => until == null
            ? _matches(t, query)
            : _matches(t, query) & _upTo(t, until),
      )
      ..orderBy(_historyOrder);
    return stmt.watch();
  }

  /// Totaux revenus / dépenses non supprimés, optionnellement sur un
  /// intervalle de dates inclusif.
  Stream<TypeTotals> watchTotals(
    String? userId, {
    LocalDate? from,
    LocalDate? to,
  }) {
    final sum = transactions.amount.sum();
    final stmt = selectOnly(transactions)
      ..addColumns([transactions.type, sum])
      ..where(_alive(transactions, userId) & _range(transactions, from, to))
      ..groupBy([transactions.type]);
    return stmt.watch().map((rows) {
      var income = 0;
      var expense = 0;
      for (final row in rows) {
        final total = row.read(sum) ?? 0;
        switch (transactions.type.converter.fromSql(
          row.read(transactions.type)!,
        )) {
          case TransactionType.income:
            income = total;
          case TransactionType.expense:
            expense = total;
        }
      }
      return TypeTotals(income: income, expense: expense);
    });
  }

  /// Totaux par jour pour les dates données (en-têtes de l'historique).
  Stream<Map<String, TypeTotals>> watchDayTotals(
    TransactionQuery query,
    Set<String> days,
  ) {
    if (days.isEmpty) return Stream.value(const {});
    final sum = transactions.amount.sum();
    final stmt = selectOnly(transactions)
      ..addColumns([transactions.occurredOn, transactions.type, sum])
      ..where(
        _matches(transactions, query) & transactions.occurredOn.isIn(days),
      )
      ..groupBy([transactions.occurredOn, transactions.type]);
    return stmt.watch().map(_groupTotals(transactions.occurredOn, sum));
  }

  /// Totaux par mois `YYYY-MM` entre deux mois inclus (graphique en barres).
  Stream<Map<String, TypeTotals>> watchMonthlyTotals(
    String? userId,
    YearMonth from,
    YearMonth to,
  ) {
    final month = transactions.occurredOn.substr(1, 7);
    final sum = transactions.amount.sum();
    final stmt = selectOnly(transactions)
      ..addColumns([month, transactions.type, sum])
      ..where(
        _alive(transactions, userId) &
            _range(transactions, from.firstDay, to.lastDay),
      )
      ..groupBy([month, transactions.type]);
    return stmt.watch().map(_groupTotals(month, sum));
  }

  /// Dépenses par jour d'un intervalle (courbe cumulée).
  Stream<Map<String, int>> watchDailyExpenses(
    String? userId,
    LocalDate from,
    LocalDate to,
  ) {
    final sum = transactions.amount.sum();
    final stmt = selectOnly(transactions)
      ..addColumns([transactions.occurredOn, sum])
      ..where(
        _alive(transactions, userId) &
            transactions.type.equalsValue(TransactionType.expense) &
            _range(transactions, from, to),
      )
      ..groupBy([transactions.occurredOn]);
    return stmt.watch().map(
      (rows) => {
        for (final row in rows)
          row.read(transactions.occurredOn)!: row.read(sum) ?? 0,
      },
    );
  }

  /// Répartition par catégorie d'un type d'opération, triée par montant
  /// décroissant. Les catégories archivées restent incluses (§3.G).
  Stream<List<CategoryTotal>> watchTotalsByCategory(
    String? userId,
    TransactionType type,
    LocalDate from,
    LocalDate to,
  ) {
    final sum = transactions.amount.sum();
    final stmt =
        selectOnly(transactions).join([
            innerJoin(
              categories,
              categories.id.equalsExp(transactions.categoryId),
            ),
          ])
          ..addColumns([categories.id, categories.name, categories.icon, sum])
          ..where(
            _alive(transactions, userId) &
                transactions.type.equalsValue(type) &
                _range(transactions, from, to),
          )
          ..groupBy([categories.id])
          ..orderBy([OrderingTerm.desc(sum)]);
    return stmt.watch().map(
      (rows) => [
        for (final row in rows)
          CategoryTotal(
            categoryId: row.read(categories.id)!,
            name: row.read(categories.name)!,
            icon: row.read(categories.icon)!,
            total: row.read(sum) ?? 0,
          ),
      ],
    );
  }

  /// Catégorie de la dernière opération saisie de ce type (présélection du
  /// formulaire, §3.E).
  Future<String?> lastUsedCategoryId(String? userId, TransactionType type) =>
      (select(transactions)
            ..where((t) => _alive(t, userId) & t.type.equalsValue(type))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(1))
          .map((t) => t.categoryId)
          .getSingleOrNull();

  Future<int> countAlive(String? userId) {
    final count = transactions.id.count();
    return (selectOnly(transactions)
          ..addColumns([count])
          ..where(_alive(transactions, userId)))
        .map((row) => row.read(count)!)
        .getSingle();
  }

  Future<bool> isCategoryUsed(String categoryId) async {
    final row =
        await (select(transactions)
              ..where((t) => t.categoryId.equals(categoryId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  // ---------------------------------------------------------------------------

  static List<OrderClauseGenerator<$TransactionsTable>> get _historyOrder => [
    (t) => OrderingTerm.desc(t.occurredOn),
    (t) => OrderingTerm.desc(t.createdAt),
    (t) => OrderingTerm.desc(t.id),
  ];

  Expression<bool> _alive($TransactionsTable t, String? userId) =>
      t.deletedAt.isNull() & ownedBy(t.userId, userId);

  Expression<bool> _range(
    $TransactionsTable t,
    LocalDate? from,
    LocalDate? to,
  ) {
    Expression<bool> e = const Constant(true);
    if (from != null) {
      e = e & t.occurredOn.isBiggerOrEqualValue(from.toIso());
    }
    if (to != null) e = e & t.occurredOn.isSmallerOrEqualValue(to.toIso());
    return e;
  }

  Expression<bool> _matches($TransactionsTable t, TransactionQuery q) {
    var e = _alive(t, q.userId) & _range(t, q.from, q.to);
    if (q.type != null) e = e & t.type.equalsValue(q.type);
    if (q.categoryIds.isNotEmpty) e = e & t.categoryId.isIn(q.categoryIds);
    final search = q.search == null ? '' : normalizeForSearch(q.search!);
    if (search.isNotEmpty) {
      e = e & t.noteSearch.like('%${escapeLike(search)}%', escapeChar: r'\');
    }
    return e;
  }

  /// Affichées strictement après [c] (clés plus petites, ordre décroissant).
  Expression<bool> _after($TransactionsTable t, HistoryCursor c) =>
      t.occurredOn.isSmallerThanValue(c.occurredOn) |
      (t.occurredOn.equals(c.occurredOn) &
          (t.createdAt.isSmallerThanValue(c.createdAt) |
              (t.createdAt.equals(c.createdAt) &
                  t.id.isSmallerThanValue(c.id))));

  /// Affichées avant [c] ou égale à [c] (clés plus grandes ou égales).
  Expression<bool> _upTo($TransactionsTable t, HistoryCursor c) =>
      t.occurredOn.isBiggerThanValue(c.occurredOn) |
      (t.occurredOn.equals(c.occurredOn) &
          (t.createdAt.isBiggerThanValue(c.createdAt) |
              (t.createdAt.equals(c.createdAt) &
                  t.id.isBiggerOrEqualValue(c.id))));

  Map<String, TypeTotals> Function(List<TypedResult>) _groupTotals(
    Expression<String> key,
    Expression<int> sum,
  ) => (rows) {
    final result = <String, TypeTotals>{};
    for (final row in rows) {
      final k = row.read(key)!;
      final total = row.read(sum) ?? 0;
      final previous = result[k] ?? TypeTotals.zero;
      final type = transactions.type.converter.fromSql(
        row.read(transactions.type)!,
      );
      result[k] = type == TransactionType.income
          ? TypeTotals(income: total, expense: previous.expense)
          : TypeTotals(income: previous.income, expense: total);
    }
    return result;
  };
}
