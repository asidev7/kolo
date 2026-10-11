import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../app/theme/kolo_typography.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/kolo_card.dart';
import '../../../core/widgets/period_selector.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/tab_scaffold.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/statistics_repository.dart';

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => StatisticsRepository(ref.watch(databaseProvider)),
);

final expenseSharesProvider = StreamProvider.autoDispose
    .family<List<CategoryShare>, YearMonth>(
      (ref, month) => ref
          .watch(statisticsRepositoryProvider)
          .watchExpenseShares(ref.watch(currentOwnerProvider), month),
    );

final monthlyPointsProvider = StreamProvider.autoDispose
    .family<List<MonthlyPoint>, YearMonth>(
      (ref, month) => ref
          .watch(statisticsRepositoryProvider)
          .watchMonthly(ref.watch(currentOwnerProvider), month),
    );

final cumulativeExpensesProvider = StreamProvider.autoDispose
    .family<List<int>, YearMonth>(
      (ref, month) => ref
          .watch(statisticsRepositoryProvider)
          .watchCumulativeExpenses(ref.watch(currentOwnerProvider), month),
    );

/// Statistiques (§3.H).
///
/// Les graphiques reçoivent des `double` : c'est une exigence de `fl_chart`
/// pour le **rendu** uniquement. Tous les montants affichés en texte et tous
/// les pourcentages viennent de calculs entiers.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final current = ref.watch(timeSourceProvider).currentMonth();
    final totals = ref.watch(allTimeTotalsProvider).value;
    final hasAnyData =
        totals == null || totals.income > 0 || totals.expense > 0;

    return KoloTabScaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: !hasAnyData
          ? EmptyState(
              icon: Icons.insights_rounded,
              title: 'Pas encore de statistiques',
              message:
                  'Ajoute ta première opération pour voir tes statistiques.',
              actionLabel: 'Ajouter une opération',
              onAction: () => context.push(Routes.newTransaction),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                KoloSpacing.lg,
                0,
                KoloSpacing.lg,
                bottomBarInset(context),
              ),
              children: [
                Center(
                  child: PeriodSelector(
                    value: month,
                    current: current,
                    onChanged: ref.read(selectedMonthProvider.notifier).select,
                  ),
                ),
                const SizedBox(height: KoloSpacing.sm),
                _ExpenseBreakdown(month: month),
                const SizedBox(height: KoloSpacing.lg),
                _MonthlyBars(month: month),
                const SizedBox(height: KoloSpacing.lg),
                _CumulativeLine(month: month),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: KoloSpacing.lg),
          child,
        ],
      ),
    );
  }
}

Widget _asyncSection<T>(
  AsyncValue<T> value,
  VoidCallback retry,
  Widget Function(T) builder,
) => switch (value) {
  AsyncValue(:final value?) => builder(value),
  AsyncValue(:final error?) => ErrorState(error: error, onRetry: retry),
  _ => const SizedBox(height: 160, child: LoadingState()),
};

class _ExpenseBreakdown extends ConsumerWidget {
  const _ExpenseBreakdown({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(expenseSharesProvider(month));
    return _Section(
      title: 'Dépenses par catégorie',
      child: _asyncSection(
        shares,
        () => ref.invalidate(expenseSharesProvider(month)),
        (list) {
          if (list.isEmpty) {
            return const EmptyState(
              compact: true,
              icon: Icons.donut_large_rounded,
              title: 'Aucune dépense ce mois-ci',
              message: 'Tes dépenses du mois seront réparties ici.',
            );
          }
          final total = list.fold<int>(0, (a, s) => a + s.total);
          return Column(
            children: [
              SizedBox(
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 56,
                        sections: [
                          for (final (i, s) in list.indexed)
                            PieChartSectionData(
                              value: s.total.toDouble(),
                              color: _colorAt(i),
                              radius: 28,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Total', style: KoloTypography.caption),
                        AmountText(total),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KoloSpacing.lg),
              for (final (i, s) in list.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: KoloSpacing.xs),
                  child: Row(
                    children: [
                      CategoryIcon(
                        iconKey: s.icon,
                        size: 32,
                        color: _colorAt(i),
                        background: _colorAt(i).withValues(alpha: 0.12),
                      ),
                      const SizedBox(width: KoloSpacing.md),
                      Expanded(
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${s.percent} %', style: KoloTypography.caption),
                      const SizedBox(width: KoloSpacing.md),
                      AmountText(s.total),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _colorAt(int i) => KoloColors.chart[i % KoloColors.chart.length];
}

class _MonthlyBars extends ConsumerWidget {
  const _MonthlyBars({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(monthlyPointsProvider(month));
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;
    return _Section(
      title: 'Revenus et dépenses (6 mois)',
      child: _asyncSection(
        points,
        () => ref.invalidate(monthlyPointsProvider(month)),
        (list) {
          final maxValue = list.fold<int>(
            0,
            (m, p) => math.max(m, math.max(p.totals.income, p.totals.expense)),
          );
          return Column(
            children: [
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    maxY: maxValue == 0 ? 1 : maxValue * 1.15,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, _, rod, rodIndex) =>
                            BarTooltipItem(
                              formatMoney(rod.toY.round(), currency: currency),
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= list.length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                KoloDates.shortMonth(list[i].month),
                                style: KoloTypography.caption.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (final (i, p) in list.indexed)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 4,
                          barRods: [
                            BarChartRodData(
                              toY: p.totals.income.toDouble(),
                              color: KoloColors.positive,
                              width: 10,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            BarChartRodData(
                              toY: p.totals.expense.toDouble(),
                              color: KoloColors.negative,
                              width: 10,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: KoloSpacing.md),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Legend(color: KoloColors.positive, label: 'Revenus'),
                  SizedBox(width: KoloSpacing.lg),
                  _Legend(color: KoloColors.negative, label: 'Dépenses'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CumulativeLine extends ConsumerWidget {
  const _CumulativeLine({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref.watch(cumulativeExpensesProvider(month));
    final today = ref.watch(timeSourceProvider).today();
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;
    return _Section(
      title: 'Évolution des dépenses du mois',
      child: _asyncSection(
        values,
        () => ref.invalidate(cumulativeExpensesProvider(month)),
        (list) {
          // Mois en cours : on n'extrapole pas au-delà d'aujourd'hui.
          final lastDay = month == today.yearMonth ? today.day : list.length;
          final shown = list.take(lastDay).toList();
          final total = shown.isEmpty ? 0 : shown.last;
          if (total == 0) {
            return const EmptyState(
              compact: true,
              icon: Icons.show_chart_rounded,
              title: 'Aucune dépense ce mois-ci',
              message: 'La courbe se dessinera au fil de tes dépenses.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Cumul : ', style: KoloTypography.caption),
                  AmountText(total, color: KoloColors.negative),
                ],
              ),
              const SizedBox(height: KoloSpacing.md),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    minX: 1,
                    maxX: list.length.toDouble(),
                    minY: 0,
                    maxY: total * 1.1,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 7,
                          reservedSize: 24,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(
                              value.toInt().toString(),
                              style: KoloTypography.caption.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => [
                          for (final s in spots)
                            LineTooltipItem(
                              'Jour ${s.x.toInt()} : ${formatMoney(s.y.round(), currency: currency)}',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (final (i, v) in shown.indexed)
                            FlSpot(i + 1, v.toDouble()),
                        ],
                        color: KoloColors.negative,
                        barWidth: 2.5,
                        isCurved: false,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: KoloColors.negative.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: KoloSpacing.xs),
        Text(label, style: KoloTypography.caption),
      ],
    );
  }
}
