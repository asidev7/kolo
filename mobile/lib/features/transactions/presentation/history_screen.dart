import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../app/theme/kolo_typography.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/errors/failures.dart';
import '../../../core/model/enums.dart';
import '../../../core/model/totals.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/tab_scaffold.dart';
import '../../auth/presentation/session_controller.dart';
import '../../categories/domain/category.dart';
import '../domain/transaction.dart';
import 'history_controller.dart';
import 'widgets/transaction_tile.dart';

/// Historique des opérations (§3.F).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(historyFilterProvider).search;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) {
      unawaited(ref.read(historyProvider.notifier).loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final filter = ref.read(historyFilterProvider);
      ref
          .read(historyFilterProvider.notifier)
          .update(filter.copyWith(search: value));
    });
  }

  Future<bool> _confirmDelete(KoloTransaction tx) async {
    final currency = ref.read(currencyProvider).value ?? Currencies.defaultCurrency;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Supprimer cette opération ?',
      message:
          '${formatSignedAmount(tx.amount, tx.type, currency: currency)} du '
          '${KoloDates.short(tx.occurredOn)} disparaîtra de tes totaux.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed) return false;
    try {
      await ref
          .read(transactionsRepositoryProvider)
          .delete(id: tx.id, ownerId: ref.read(currentOwnerProvider));
      rootMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Opération supprimée')),
      );
    } on Object catch (e) {
      rootMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(userMessageFor(e))),
      );
    }
    // La liste se met à jour par le stream : on ne retire pas la ligne
    // nous-mêmes (évite une incohérence en cas d'échec).
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    final history = ref.watch(historyProvider);
    final lookup = ref.watch(categoryLookupProvider).value ?? const {};
    final today = ref.watch(timeSourceProvider).today();

    return KoloTabScaffold(
      appBar: AppBar(title: const Text('Historique')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter une opération',
        onPressed: () => context.push(Routes.newTransaction),
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KoloSpacing.lg,
              0,
              KoloSpacing.lg,
              KoloSpacing.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher dans les notes',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          _FilterBar(filter: filter, lookup: lookup),
          Expanded(
            child: history.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(
                error: e,
                onRetry: () => ref.invalidate(historyProvider),
              ),
              data: (state) {
                if (state.items.isEmpty) {
                  return filter.isActive
                      ? EmptyState(
                          icon: Icons.filter_alt_off_rounded,
                          title: 'Aucun résultat',
                          message:
                              'Aucune opération ne correspond à ces filtres.',
                          actionLabel: 'Réinitialiser les filtres',
                          onAction: () {
                            _search.clear();
                            ref.read(historyFilterProvider.notifier).reset();
                          },
                        )
                      : EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'Aucune opération',
                          message:
                              'Tes revenus et tes dépenses apparaîtront ici.',
                          actionLabel: 'Ajouter une opération',
                          onAction: () => context.push(Routes.newTransaction),
                        );
                }
                return _GroupedList(
                  controller: _scroll,
                  state: state,
                  lookup: lookup,
                  today: today,
                  onTap: (tx) => context.push(Routes.editTransaction(tx.id)),
                  confirmDelete: _confirmDelete,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _Row {
  const _Row();
}

class _DayRow extends _Row {
  const _DayRow(this.day);

  final String day;
}

class _TxRow extends _Row {
  const _TxRow(this.tx);

  final KoloTransaction tx;
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.controller,
    required this.state,
    required this.lookup,
    required this.today,
    required this.onTap,
    required this.confirmDelete,
  });

  final ScrollController controller;
  final HistoryState state;
  final Map<String, KoloCategory> lookup;
  final LocalDate today;
  final ValueChanged<KoloTransaction> onTap;
  final Future<bool> Function(KoloTransaction) confirmDelete;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[];
    String? currentDay;
    for (final tx in state.items) {
      final day = tx.occurredOn.toIso();
      if (day != currentDay) {
        rows.add(_DayRow(day));
        currentDay = day;
      }
      rows.add(_TxRow(tx));
    }

    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.only(bottom: bottomBarInset(context)),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return state.hasMore
              ? const Padding(
                  padding: EdgeInsets.all(KoloSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox(height: KoloSpacing.lg);
        }
        return switch (rows[index]) {
          _DayRow(:final day) => _DayHeader(
            label: KoloDates.dayHeader(LocalDate.parse(day), today),
            totals: state.dayTotals[day],
          ),
          _TxRow(:final tx) => Dismissible(
            key: ValueKey(tx.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => confirmDelete(tx),
            background: Container(
              color: KoloColors.negativeSoft,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: KoloSpacing.xl),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: KoloColors.negative,
              ),
            ),
            child: ColoredBox(
              color: KoloColors.surface,
              child: TransactionTile(
                transaction: tx,
                category: lookup[tx.categoryId],
                onTap: () => onTap(tx),
              ),
            ),
          ),
        };
      },
    );
  }
}

class _DayHeader extends ConsumerWidget {
  const _DayHeader({required this.label, required this.totals});

  final String label;
  final TypeTotals? totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = totals == null ? null : totals!.income - totals!.expense;
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;
    return Semantics(
      header: true,
      child: Container(
        color: KoloColors.background,
        padding: const EdgeInsets.fromLTRB(
          KoloSpacing.lg,
          KoloSpacing.lg,
          KoloSpacing.lg,
          KoloSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: KoloTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (net != null)
              Text(
                '${net > 0 ? '+' : ''}${formatMoney(net, currency: currency)}',
                style: KoloTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: KoloTypography.tabular,
                  color: net < 0
                      ? KoloColors.negative
                      : net > 0
                      ? KoloColors.positive
                      : KoloColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Puces de filtres : type, période, catégories, réinitialisation.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter, required this.lookup});

  final HistoryFilter filter;
  final Map<String, KoloCategory> lookup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyFilterProvider.notifier);
    final periodLabel = switch (filter.period) {
      HistoryPeriod.all => 'Toutes les dates',
      HistoryPeriod.thisMonth => 'Ce mois-ci',
      HistoryPeriod.lastMonth => 'Mois dernier',
      HistoryPeriod.custom =>
        '${filter.from == null ? '…' : KoloDates.short(filter.from!)} – '
            '${filter.to == null ? '…' : KoloDates.short(filter.to!)}',
    };
    final typeLabel = switch (filter.type) {
      null => 'Tous les types',
      TransactionType.expense => 'Dépenses',
      TransactionType.income => 'Revenus',
    };
    final categoryLabel = filter.categoryIds.isEmpty
        ? 'Catégories'
        : filter.categoryIds.length == 1
        ? lookup[filter.categoryIds.first]?.name ?? '1 catégorie'
        : '${filter.categoryIds.length} catégories';

    // Quatre puces au plus : une rangée défilante simple, sans
    // construction paresseuse.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: KoloSpacing.lg),
      child: Row(
        children: [
          FilterChip(
            label: Text(typeLabel),
            selected: filter.type != null,
            onSelected: (_) async {
              final picked = await _pick<TransactionType?>(
                context,
                title: "Type d'opération",
                options: const {
                  null: 'Tous les types',
                  TransactionType.expense: 'Dépenses',
                  TransactionType.income: 'Revenus',
                },
                current: filter.type,
              );
              if (picked != null) {
                notifier.update(filter.copyWith(type: () => picked.value));
              }
            },
          ),
          const SizedBox(width: KoloSpacing.sm),
          FilterChip(
            label: Text(periodLabel),
            selected: filter.period != HistoryPeriod.all,
            onSelected: (_) => _pickPeriod(context, ref),
          ),
          const SizedBox(width: KoloSpacing.sm),
          FilterChip(
            label: Text(categoryLabel),
            selected: filter.categoryIds.isNotEmpty,
            onSelected: (_) => _pickCategories(context, ref),
          ),
          if (filter.isActive) ...[
            const SizedBox(width: KoloSpacing.sm),
            ActionChip(
              avatar: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Réinitialiser'),
              onPressed: notifier.reset,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickPeriod(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(historyFilterProvider.notifier);
    final picked = await _pick<HistoryPeriod>(
      context,
      title: 'Période',
      options: const {
        HistoryPeriod.all: 'Toutes les dates',
        HistoryPeriod.thisMonth: 'Ce mois-ci',
        HistoryPeriod.lastMonth: 'Mois dernier',
        HistoryPeriod.custom: 'Choisir des dates…',
      },
      current: filter.period,
    );
    if (picked == null || !context.mounted) return;
    if (picked.value != HistoryPeriod.custom) {
      notifier.update(filter.copyWith(period: picked.value));
      return;
    }
    final today = ref.read(timeSourceProvider).today();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today.addDays(1).toDateTime(),
      helpText: 'Période',
    );
    if (range == null) return;
    notifier.update(
      filter.copyWith(
        period: HistoryPeriod.custom,
        from: () => LocalDate.fromDateTime(range.start),
        to: () => LocalDate.fromDateTime(range.end),
      ),
    );
  }

  Future<void> _pickCategories(BuildContext context, WidgetRef ref) async {
    final categories = lookup.values.toList()
      ..sort((a, b) {
        final byType = a.type.index.compareTo(b.type.index);
        return byType != 0 ? byType : a.name.compareTo(b.name);
      });
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CategoryPicker(categories: categories, initial: filter.categoryIds),
    );
    if (selected == null) return;
    ref
        .read(historyFilterProvider.notifier)
        .update(filter.copyWith(categoryIds: selected));
  }
}

/// Enveloppe pour distinguer « aucun choix » de « choix de `null` ».
class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

Future<_Picked<T>?> _pick<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T current,
}) => showModalBottomSheet<_Picked<T>>(
  context: context,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KoloSpacing.xl,
            0,
            KoloSpacing.xl,
            KoloSpacing.sm,
          ),
          child: Text(title, style: KoloTypography.subtitle),
        ),
        for (final entry in options.entries)
          ListTile(
            title: Text(entry.value),
            trailing: entry.key == current
                ? const Icon(Icons.check_rounded, color: KoloColors.primary)
                : null,
            onTap: () => Navigator.of(context).pop(_Picked(entry.key)),
          ),
        const SizedBox(height: KoloSpacing.sm),
      ],
    ),
  ),
);

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.categories, required this.initial});

  final List<KoloCategory> categories;
  final Set<String> initial;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoloSpacing.xl),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Catégories', style: KoloTypography.subtitle),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Aucune'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                for (final c in widget.categories)
                  CheckboxListTile(
                    value: _selected.contains(c.id),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _selected.add(c.id)
                          : _selected.remove(c.id),
                    ),
                    secondary: CategoryIcon(iconKey: c.icon, size: 32),
                    title: Text(c.name),
                    subtitle: Text(
                      [
                        if (c.type == TransactionType.expense)
                          'Dépense'
                        else
                          'Revenu',
                        if (c.isArchived) 'archivée',
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(KoloSpacing.lg),
              child: KoloButton(
                label: 'Appliquer',
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
