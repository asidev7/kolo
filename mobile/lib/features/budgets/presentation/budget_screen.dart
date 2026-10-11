import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../app/providers.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/errors/failures.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/budget.dart';
import 'widgets/budget_summary.dart';

/// Seuils proposés à l'utilisateur.
const _thresholdChoices = [50, 70, 80, 90, 100];

/// Budget mensuel global (§3.I).
///
/// Le plafond saisi s'applique au mois courant et est reconduit les mois
/// suivants tant qu'il n'est pas modifié. Dépasser le budget n'empêche
/// jamais d'enregistrer une dépense.
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  final _amount = TextEditingController();
  Set<int> _thresholds = {...Budget.defaultThresholds};
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _initFrom(Budget? budget) {
    if (_initialized) return;
    _initialized = true;
    if (budget != null) {
      final currency = ref.read(currencyProvider).value ?? Currencies.defaultCurrency;
      _amount.text = budget.limitAmount == 0
          ? ''
          : formatMoney(budget.limitAmount, currency: currency, showSymbol: false);
      _thresholds = {...budget.alertThresholds};
    }
  }

  Future<void> _save() async {
    final currency = ref.read(currencyProvider).value ?? Currencies.defaultCurrency;
    final amount = parseAmountInput(_amount.text, currency: currency) ?? 0;
    if (_thresholds.isEmpty) {
      setState(() => _error = 'Choisis au moins un seuil d’alerte.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final month = ref.read(timeSourceProvider).currentMonth();
    final owner = ref.read(currentOwnerProvider);
    try {
      await ref
          .read(budgetsRepositoryProvider)
          .setMonthlyLimit(
            ownerId: owner,
            month: month,
            limitAmount: amount,
            thresholds: _thresholds.toList(),
          );
      final alerts = ref.read(budgetAlertServiceProvider);
      if (amount > 0 && await alerts.alertsEnabled()) {
        await ref.read(localNotifierProvider).requestPermission();
      }
      unawaited(alerts.check(ownerId: owner, month: month));
      if (!mounted) return;
      context.pop();
      rootMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(amount == 0 ? 'Budget retiré' : 'Budget enregistré'),
        ),
      );
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.fields.values.first);
    } on Object catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(timeSourceProvider).currentMonth();
    final budget = ref.watch(effectiveBudgetProvider(month));
    final status = ref.watch(budgetStatusProvider(month));
    final theme = Theme.of(context);
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;

    return Scaffold(
      appBar: AppBar(title: const Text('Budget du mois')),
      body: SafeArea(
        child: budget.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(effectiveBudgetProvider(month)),
          ),
          data: (b) {
            _initFrom(b);
            return ListView(
              padding: const EdgeInsets.all(KoloSpacing.lg),
              children: [
                if (status.value case final s?)
                  KoloCard(child: BudgetSummary(status: s)),
                const SizedBox(height: KoloSpacing.xl),
                Text('Plafond mensuel', style: theme.textTheme.titleMedium),
                const SizedBox(height: KoloSpacing.xs),
                Text(
                  'S’applique à partir de '
                  '${KoloDates.monthLabel(month).toLowerCase()} et les mois '
                  'suivants, tant que tu ne le changes pas. Laisse vide pour '
                  'retirer le budget.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: KoloSpacing.md),
                KoloCard(
                  child: AmountField(
                    key: const Key('budget-amount'),
                    controller: _amount,
                    currency: currency,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(height: KoloSpacing.xl),
                Text('Alertes', style: theme.textTheme.titleMedium),
                const SizedBox(height: KoloSpacing.xs),
                Text(
                  'Tu reçois une notification une seule fois par seuil et par '
                  'mois.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: KoloSpacing.md),
                Wrap(
                  spacing: KoloSpacing.sm,
                  runSpacing: KoloSpacing.sm,
                  children: [
                    for (final t in _thresholdChoices)
                      FilterChip(
                        label: Text('$t %'),
                        selected: _thresholds.contains(t),
                        onSelected: (on) => setState(() {
                          on ? _thresholds.add(t) : _thresholds.remove(t);
                          _error = null;
                        }),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: KoloSpacing.md),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: KoloColors.negative,
                    ),
                  ),
                ],
                const SizedBox(height: KoloSpacing.xxl),
                KoloButton(
                  label: 'Enregistrer le budget',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
