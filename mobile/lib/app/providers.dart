import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/currencies.dart';
import '../core/model/enums.dart';
import '../core/providers/core_providers.dart';
import '../core/utils/local_date.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/budgets/data/budget_alert_service.dart';
import '../features/budgets/data/budget_notifier.dart';
import '../features/budgets/data/budgets_repository.dart';
import '../features/budgets/domain/budget.dart';
import '../features/categories/data/categories_repository.dart';
import '../features/categories/domain/category.dart';
import '../features/settings/data/settings_keys.dart';
import '../features/transactions/data/transactions_repository.dart';
import '../features/transactions/domain/finance.dart';
import '../features/transactions/domain/transaction.dart';
import '../synchronization/sync_providers.dart';

// -----------------------------------------------------------------------------
// Repositories
// -----------------------------------------------------------------------------

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => TransactionsRepository(
    db: ref.watch(databaseProvider),
    writer: ref.watch(outboxWriterProvider),
    time: ref.watch(timeSourceProvider),
    onLocalWrite: ref.watch(localWriteSignalProvider),
  ),
);

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(
    db: ref.watch(databaseProvider),
    writer: ref.watch(outboxWriterProvider),
    time: ref.watch(timeSourceProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final budgetsRepositoryProvider = Provider<BudgetsRepository>(
  (ref) => BudgetsRepository(
    db: ref.watch(databaseProvider),
    writer: ref.watch(outboxWriterProvider),
    time: ref.watch(timeSourceProvider),
    ids: ref.watch(idGeneratorProvider),
    onLocalWrite: ref.watch(localWriteSignalProvider),
  ),
);

final localNotifierProvider = Provider<LocalNotifier>(
  (ref) => PluginLocalNotifier(),
);

final budgetAlertServiceProvider = Provider<BudgetAlertService>(
  (ref) => BudgetAlertService(
    db: ref.watch(databaseProvider),
    budgets: ref.watch(budgetsRepositoryProvider),
    notifier: ref.watch(localNotifierProvider),
  ),
);

/// Devise choisie par l'utilisateur (§5.1). Absente → XOF.
final currencyProvider = StreamProvider<Currency>(
  (ref) => ref
      .watch(databaseProvider)
      .settingsDao
      .watch(SettingsKeys.currencyCode)
      .map((code) => Currencies.of(code ?? Currencies.defaultCurrency.code)),
);

// -----------------------------------------------------------------------------
// Lectures réactives (toujours depuis SQLite, §4.1)
// -----------------------------------------------------------------------------

/// Mois sélectionné, partagé par le tableau de bord et les statistiques.
final selectedMonthProvider = NotifierProvider<SelectedMonth, YearMonth>(
  SelectedMonth.new,
);

class SelectedMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => ref.watch(timeSourceProvider).currentMonth();

  void select(YearMonth month) {
    final current = ref.read(timeSourceProvider).currentMonth();
    state = month.compareTo(current) > 0 ? current : month;
  }
}

/// Totaux toutes périodes confondues (solde net enregistré).
final allTimeTotalsProvider = StreamProvider<TypeTotals>((ref) {
  final owner = ref.watch(currentOwnerProvider);
  return ref.watch(databaseProvider).transactionsDao.watchTotals(owner);
});

final monthTotalsProvider = StreamProvider.autoDispose
    .family<TypeTotals, YearMonth>((ref, month) {
      final owner = ref.watch(currentOwnerProvider);
      return ref
          .watch(databaseProvider)
          .transactionsDao
          .watchTotals(owner, from: month.firstDay, to: month.lastDay);
    });

final recentTransactionsProvider = StreamProvider<List<KoloTransaction>>((ref) {
  final owner = ref.watch(currentOwnerProvider);
  return ref.watch(transactionsRepositoryProvider).watchRecent(owner);
});

final effectiveBudgetProvider = StreamProvider.autoDispose
    .family<Budget?, YearMonth>((ref, month) {
      final owner = ref.watch(currentOwnerProvider);
      return ref.watch(budgetsRepositoryProvider).watchEffective(owner, month);
    });

final budgetStatusProvider = Provider.autoDispose
    .family<AsyncValue<BudgetStatus>, YearMonth>((ref, month) {
      final budget = ref.watch(effectiveBudgetProvider(month));
      final totals = ref.watch(monthTotalsProvider(month));
      return combine2(
        budget,
        totals,
        (b, t) => BudgetStatus.compute(
          limit: b?.limitAmount,
          spent: t.expense,
          thresholds: b?.alertThresholds ?? Budget.defaultThresholds,
        ),
      );
    });

/// Catégories proposées à la saisie, par type.
final activeCategoriesProvider = StreamProvider.autoDispose
    .family<List<KoloCategory>, TransactionType?>((ref, type) {
      final owner = ref.watch(currentOwnerProvider);
      return ref
          .watch(categoriesRepositoryProvider)
          .watchActive(owner, type: type);
    });

/// Toutes les catégories visibles (archivées comprises), par identifiant.
final categoryLookupProvider = StreamProvider<Map<String, KoloCategory>>((ref) {
  final owner = ref.watch(currentOwnerProvider);
  return ref.watch(categoriesRepositoryProvider).watchLookup(owner);
});

/// Combine deux valeurs asynchrones : erreur si l'une échoue, chargement si
/// l'une n'a encore jamais produit de valeur. Une valeur précédente est
/// conservée pendant un rafraîchissement (pas de clignotement).
AsyncValue<R> combine2<A, B, R>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  R Function(A, B) combine,
) {
  if (a.hasError && !a.hasValue) return AsyncError(a.error!, a.stackTrace!);
  if (b.hasError && !b.hasValue) return AsyncError(b.error!, b.stackTrace!);
  if (a.hasValue && b.hasValue) {
    return AsyncData(combine(a.requireValue, b.requireValue));
  }
  return const AsyncLoading();
}
