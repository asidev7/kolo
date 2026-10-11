import 'package:flutter/material.dart';

import '../../../../app/theme/kolo_colors.dart';
import '../../../../app/theme/kolo_tokens.dart';
import '../../../../app/theme/kolo_typography.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../domain/budget.dart';

/// Résumé du budget : barre, % consommé, restant (rouge si négatif).
class BudgetSummary extends StatelessWidget {
  const BudgetSummary({required this.status, super.key});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!status.hasBudget) {
      return Row(
        children: [
          const Icon(Icons.savings_outlined, color: KoloColors.primary),
          const SizedBox(width: KoloSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aucun budget défini', style: theme.textTheme.titleSmall),
                Text(
                  'Fixe un plafond pour suivre tes dépenses du mois.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: KoloColors.textSecondary,
          ),
        ],
      );
    }
    final color = switch (status.level) {
      BudgetLevel.exceeded => KoloColors.negative,
      BudgetLevel.warning => KoloColors.warning,
      _ => KoloColors.positive,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Budget du mois', style: theme.textTheme.titleSmall),
            ),
            Text(
              '${status.percent} %',
              style: KoloTypography.amount.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: KoloSpacing.sm),
        Semantics(
          label: 'Budget consommé à ${status.percent} %',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: status.progress,
              minHeight: 8,
              color: color,
              backgroundColor: KoloColors.border,
            ),
          ),
        ),
        const SizedBox(height: KoloSpacing.sm),
        Row(
          children: [
            Text(
              status.remaining < 0 ? 'Dépassement : ' : 'Restant : ',
              style: theme.textTheme.bodySmall,
            ),
            Flexible(
              child: AmountText(
                status.remaining,
                style: KoloTypography.amount.copyWith(fontSize: 13),
                color: status.remaining < 0 ? KoloColors.negative : null,
              ),
            ),
            const Spacer(),
            Text('sur ', style: theme.textTheme.bodySmall),
            AmountText(
              status.limit,
              style: KoloTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
