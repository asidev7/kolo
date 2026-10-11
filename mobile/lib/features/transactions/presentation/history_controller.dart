import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/model/enums.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../database/app_database.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';

/// Période proposée par le filtre de l'historique.
enum HistoryPeriod { all, thisMonth, lastMonth, custom }

/// Filtres combinables de l'historique (§3.F).
@immutable
class HistoryFilter {
  const HistoryFilter({
    this.type,
    this.period = HistoryPeriod.all,
    this.from,
    this.to,
    this.categoryIds = const {},
    this.search = '',
  });

  final TransactionType? type;
  final HistoryPeriod period;

  /// Bornes de la période personnalisée.
  final LocalDate? from;
  final LocalDate? to;
  final Set<String> categoryIds;
  final String search;

  bool get isActive =>
      type != null ||
      period != HistoryPeriod.all ||
      categoryIds.isNotEmpty ||
      search.trim().isNotEmpty;

  HistoryFilter copyWith({
    TransactionType? Function()? type,
    HistoryPeriod? period,
    LocalDate? Function()? from,
    LocalDate? Function()? to,
    Set<String>? categoryIds,
    String? search,
  }) => HistoryFilter(
    type: type != null ? type() : this.type,
    period: period ?? this.period,
    from: from != null ? from() : this.from,
    to: to != null ? to() : this.to,
    categoryIds: categoryIds ?? this.categoryIds,
    search: search ?? this.search,
  );

  /// Requête DAO correspondante, pour le propriétaire et la date du jour
  /// donnés.
  TransactionQuery toQuery(String? ownerId, LocalDate today) {
    final (LocalDate? start, LocalDate? end) = switch (period) {
      HistoryPeriod.all => (null, null),
      HistoryPeriod.thisMonth => (
        today.yearMonth.firstDay,
        today.yearMonth.lastDay,
      ),
      HistoryPeriod.lastMonth => (
        today.yearMonth.addMonths(-1).firstDay,
        today.yearMonth.addMonths(-1).lastDay,
      ),
      HistoryPeriod.custom => (from, to),
    };
    return TransactionQuery(
      userId: ownerId,
      type: type,
      from: start,
      to: end,
      categoryIds: categoryIds,
      search: search.trim().isEmpty ? null : search,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.type == type &&
      other.period == period &&
      other.from == from &&
      other.to == to &&
      other.search == search &&
      other.categoryIds.length == categoryIds.length &&
      other.categoryIds.containsAll(categoryIds);

  @override
  int get hashCode => Object.hash(
    type,
    period,
    from,
    to,
    search,
    Object.hashAllUnordered(categoryIds),
  );
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(
      HistoryFilterController.new,
    );

class HistoryFilterController extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void update(HistoryFilter filter) => state = filter;

  void reset() => state = const HistoryFilter();
}

@immutable
class HistoryState {
  const HistoryState({
    this.items = const [],
    this.dayTotals = const {},
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<KoloTransaction> items;

  /// Totaux par jour `YYYY-MM-DD` (en-têtes de groupe).
  final Map<String, TypeTotals> dayTotals;
  final bool hasMore;
  final bool loadingMore;

  HistoryState copyWith({
    List<KoloTransaction>? items,
    Map<String, TypeTotals>? dayTotals,
    bool? hasMore,
    bool? loadingMore,
  }) => HistoryState(
    items: items ?? this.items,
    dayTotals: dayTotals ?? this.dayTotals,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Historique paginé par curseur (§3.F), 50 éléments par page.
///
/// Fonctionnement : chaque page est lue avec `pageAfter(curseur)`. Les pages
/// déjà affichées restent **réactives** grâce à `watchUntil(borne)` : une
/// saisie, une modification ou une suppression met la liste à jour sans
/// décaler la pagination.
final historyProvider = AsyncNotifierProvider<HistoryController, HistoryState>(
  HistoryController.new,
);

class HistoryController extends AsyncNotifier<HistoryState> {
  static const pageSize = 50;

  StreamSubscription<List<TransactionRow>>? _rowsSub;
  StreamSubscription<Map<String, TypeTotals>>? _totalsSub;
  late TransactionQuery _query;
  HistoryCursor? _bound;

  TransactionsDao get _dao => ref.read(databaseProvider).transactionsDao;

  @override
  Future<HistoryState> build() async {
    final filter = ref.watch(historyFilterProvider);
    final owner = ref.watch(currentOwnerProvider);
    final today = ref.watch(timeSourceProvider).today();
    ref.onDispose(_cancel);
    _cancel();

    _query = filter.toQuery(owner, today);
    final first = await _dao.pageAfter(_query, limit: pageSize + 1);
    final hasMore = first.length > pageSize;
    _bound = hasMore ? HistoryCursor.of(first[pageSize - 1]) : null;
    _listen();
    final items = first.take(pageSize).map(transactionFromRow).toList();
    return HistoryState(items: items, hasMore: hasMore);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _dao.pageAfter(
        _query,
        after: _bound,
        limit: pageSize + 1,
      );
      final hasMore = next.length > pageSize;
      _bound = hasMore ? HistoryCursor.of(next[pageSize - 1]) : null;
      final appended = next.take(pageSize).map(transactionFromRow);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...appended],
          hasMore: hasMore,
          loadingMore: false,
        ),
      );
      _listen();
    } on Object catch (e, st) {
      state = AsyncError<HistoryState>(e, st);
    }
  }

  void _listen() {
    unawaited(_rowsSub?.cancel());
    _rowsSub = _dao.watchUntil(_query, _bound).listen((rows) {
      final current = state.value ?? const HistoryState();
      final items = rows.map(transactionFromRow).toList();
      state = AsyncData(current.copyWith(items: items));
      _listenDayTotals(items);
    }, onError: (Object e, StackTrace st) => state = AsyncError(e, st));
  }

  void _listenDayTotals(List<KoloTransaction> items) {
    final days = {for (final t in items) t.occurredOn.toIso()};
    unawaited(_totalsSub?.cancel());
    _totalsSub = _dao.watchDayTotals(_query, days).listen((totals) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(dayTotals: totals));
      }
    });
  }

  void _cancel() {
    unawaited(_rowsSub?.cancel());
    unawaited(_totalsSub?.cancel());
    _rowsSub = null;
    _totalsSub = null;
  }
}
