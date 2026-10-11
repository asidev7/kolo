import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/kolo_colors.dart';
import '../../../../app/theme/kolo_tokens.dart';
import '../../../../core/constants/currencies.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../../../core/widgets/category_icon.dart';
import '../../../categories/domain/category.dart';
import '../../domain/transaction.dart';

/// Ligne d'opération : icône de catégorie, libellé, note, montant coloré,
/// pastille « en attente » si non synchronisée (§3.F).
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    required this.transaction,
    required this.category,
    super.key,
    this.onTap,
    this.subtitle,
  });

  final KoloTransaction transaction;
  final KoloCategory? category;
  final VoidCallback? onTap;

  /// Remplace la note comme sous-titre (par ex. la date).
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;
    final name = category?.name ?? 'Catégorie inconnue';
    final secondary = subtitle ?? transaction.note;
    final semantic = [
      name,
      formatSignedAmount(transaction.amount, transaction.type, currency: currency),
      ?secondary,
      if (transaction.isPending) 'en attente de synchronisation',
    ].join(', ');

    return Semantics(
      button: onTap != null,
      label: semantic,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KoloSpacing.lg,
              vertical: KoloSpacing.md,
            ),
            child: Row(
              children: [
                CategoryIcon(iconKey: category?.icon ?? 'other'),
                const SizedBox(width: KoloSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (secondary != null && secondary.isNotEmpty)
                        Text(
                          secondary,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: KoloSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(transaction.amount, type: transaction.type),
                    if (transaction.isPending) const _PendingDot(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingDot extends StatelessWidget {
  const _PendingDot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: KoloColors.warning),
          SizedBox(width: 2),
          Text(
            'en attente',
            style: TextStyle(fontSize: 11, color: KoloColors.warning),
          ),
        ],
      ),
    );
  }
}
