import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/sync.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../app/theme/kolo_typography.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_card.dart';
import '../../../core/widgets/kolo_entrance.dart';
import '../../../core/widgets/period_selector.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/sync_status_badge.dart';
import '../../../core/widgets/tab_scaffold.dart';
import '../../auth/presentation/local_mode_screen.dart';
import '../../auth/presentation/session_controller.dart';
import '../../budgets/presentation/widgets/budget_summary.dart';
import '../../transactions/domain/finance.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';

/// Tableau de bord (§3.D). Tout est lu depuis SQLite via des streams : une
/// saisie met l'écran à jour instantanément.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final month = ref.watch(selectedMonthProvider);
    final current = ref.watch(timeSourceProvider).currentMonth();
    final name = session?.displayName;

    return KoloTabScaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-transaction'),
        onPressed: () => context.push(Routes.newTransaction),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter une opération'),
      ),
      // Pas de marge basse : la liste passe sous la barre d'onglets floutée,
      // qui gère elle-même la zone sûre du bas.
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          // En mode local, rien n'est envoyé : le geste relit simplement les
          // données locales et se termine tout de suite.
          onRefresh: () async {
            await syncNow(ref);
            ref
              ..invalidate(allTimeTotalsProvider)
              ..invalidate(recentTransactionsProvider);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              KoloSpacing.lg,
              KoloSpacing.lg,
              KoloSpacing.lg,
              bottomBarInset(context),
            ),
            // Les blocs apparaissent en cascade au premier affichage (§2.3).
            children: [
              KoloEntrance(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name == null || name.isEmpty
                            ? 'Bonjour'
                            : 'Bonjour, $name',
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SyncStatusBadge(
                      state: ref.watch(syncBadgeProvider),
                      onTap: () => _showSyncInfo(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KoloSpacing.lg),
              const KoloEntrance(index: 1, child: _NetBalanceCard()),
              const SizedBox(height: KoloSpacing.lg),
              KoloEntrance(
                index: 2,
                child: Center(
                  child: PeriodSelector(
                    value: month,
                    current: current,
                    onChanged: ref.read(selectedMonthProvider.notifier).select,
                  ),
                ),
              ),
              const SizedBox(height: KoloSpacing.sm),
              KoloEntrance(index: 3, child: _MonthTotals(month: month)),
              const SizedBox(height: KoloSpacing.lg),
              KoloEntrance(index: 4, child: _BudgetCard(month: month)),
              const SizedBox(height: KoloSpacing.xl),
              const KoloEntrance(index: 5, child: _RecentTransactions()),
            ],
          ),
        ),
      ),
    );
  }

  /// Détail de l'état de synchronisation, avec le geste explicite
  /// « Synchroniser maintenant » (§3.D).
  void _showSyncInfo(BuildContext context, WidgetRef ref) {
    final badge = ref.read(syncBadgeProvider);
    final message = ref.read(syncRunStateProvider).message;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KoloSpacing.xl,
            0,
            KoloSpacing.xl,
            KoloSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Synchronisation', style: KoloTypography.subtitle),
              const SizedBox(height: KoloSpacing.md),
              Text(_syncExplanation(badge), style: KoloTypography.body),
              if (message case final error?) ...[
                const SizedBox(height: KoloSpacing.md),
                Text(
                  error,
                  style: KoloTypography.body.copyWith(
                    color: KoloColors.negative,
                  ),
                ),
              ],
              if (badge is! SyncBadgeLocal) ...[
                const SizedBox(height: KoloSpacing.lg),
                KoloButton(
                  label: 'Synchroniser maintenant',
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(syncNow(ref));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _syncExplanation(SyncBadgeState badge) => switch (badge) {
    SyncBadgeLocal() => localModeWarning,
    SyncBadgeSynced() =>
      'Tes opérations sont enregistrées sur le serveur. Tu les retrouveras '
          'sur un autre téléphone en te connectant avec le même compte.',
    SyncBadgePending(:final count) =>
      count == 1
          ? 'Une opération attend d’être envoyée.'
          : '$count opérations attendent d’être envoyées.',
    SyncBadgeOffline(:final pendingCount) =>
      pendingCount == 0
          ? 'Pas de connexion. Tes opérations seront envoyées au retour du '
                'réseau.'
          : 'Pas de connexion. $pendingCount opération'
                '${pendingCount == 1 ? '' : 's'} '
                'partira${pendingCount == 1 ? '' : 'ont'} au retour du réseau.',
    SyncBadgeError() =>
      'La dernière synchronisation a échoué. Tes opérations sont bien '
          'enregistrées sur ce téléphone ; réessaie quand tu veux.',
    SyncBadgeInProgress() => 'Envoi en cours…',
    SyncBadgeWaiting() =>
      'Ton compte est créé. La première synchronisation n’a pas encore '
          'abouti.',
  };
}

class _NetBalanceCard extends ConsumerWidget {
  const _NetBalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(allTimeTotalsProvider);
    return KoloCard(
      color: KoloColors.primary,
      borderColor: KoloColors.primary,
      padding: const EdgeInsets.all(KoloSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Solde net enregistré',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                showDuration: Duration(seconds: 6),
                message:
                    'Différence entre tous les revenus et toutes les dépenses '
                    'que tu as enregistrés dans KOLO. Ce n’est pas le solde de '
                    'ton compte bancaire ou Mobile Money.',
                child: Padding(
                  padding: EdgeInsets.all(KoloSpacing.sm),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white70,
                    size: 20,
                    semanticLabel: 'Explication du solde net enregistré',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KoloSpacing.xs),
          switch (totals) {
            AsyncValue(:final value?) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(
                Finance.netBalance(value),
                key: const Key('net-balance'),
                style: KoloTypography.display,
                color: Colors.white,
              ),
            ),
            AsyncValue(:final error?) => Text(
              'Impossible de calculer le solde.',
              semanticsLabel: error.toString(),
              style: const TextStyle(color: Colors.white),
            ),
            _ => const SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          },
        ],
      ),
    );
  }
}

class _MonthTotals extends ConsumerWidget {
  const _MonthTotals({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(monthTotalsProvider(month)).value;
    return Row(
      children: [
        Expanded(
          child: _TotalTile(
            label: 'Revenus du mois',
            amount: totals?.income,
            icon: Icons.arrow_downward_rounded,
            color: KoloColors.positive,
            background: KoloColors.positiveSoft,
          ),
        ),
        const SizedBox(width: KoloSpacing.md),
        Expanded(
          child: _TotalTile(
            label: 'Dépenses du mois',
            amount: totals?.expense,
            icon: Icons.arrow_upward_rounded,
            color: KoloColors.negative,
            background: KoloColors.negativeSoft,
          ),
        ),
      ],
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final int? amount;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: KoloSpacing.sm),
          Text(label, style: KoloTypography.caption),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: amount == null
                ? const Text('…')
                : AmountText(
                    amount!,
                    color: color,
                    style: KoloTypography.amount.copyWith(fontSize: 17),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(budgetStatusProvider(month));
    return KoloCard(
      onTap: () => context.push(Routes.budget),
      child: switch (status) {
        AsyncValue(:final value?) => BudgetSummary(status: value),
        AsyncValue(:final error?) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(effectiveBudgetProvider(month)),
        ),
        _ => const SizedBox(height: 72, child: LoadingState()),
      },
    );
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider);
    final lookup = ref.watch(categoryLookupProvider).value ?? const {};
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dernières opérations',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.go(Routes.history),
              child: const Text('Tout voir'),
            ),
          ],
        ),
        const SizedBox(height: KoloSpacing.sm),
        KoloCard(
          padding: EdgeInsets.zero,
          child: switch (recent) {
            AsyncValue(:final value?) when value.isEmpty => EmptyState(
              compact: true,
              icon: Icons.receipt_long_rounded,
              title: 'Aucune opération',
              message: 'Ajoute ta première dépense ou ton premier revenu.',
              actionLabel: 'Ajouter une opération',
              onAction: () => context.push(Routes.newTransaction),
            ),
            AsyncValue(:final value?) => Column(
              children: [
                for (final (i, tx) in value.indexed) ...[
                  if (i > 0) const Divider(indent: 68),
                  TransactionTile(
                    transaction: tx,
                    category: lookup[tx.categoryId],
                    onTap: () => context.push(Routes.editTransaction(tx.id)),
                  ),
                ],
              ],
            ),
            AsyncValue(:final error?) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(recentTransactionsProvider),
            ),
            _ => const SizedBox(height: 120, child: LoadingState()),
          },
        ),
      ],
    );
  }
}
