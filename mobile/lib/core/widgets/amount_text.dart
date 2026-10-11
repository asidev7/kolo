import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/kolo_colors.dart';
import '../../app/theme/kolo_typography.dart';
import '../constants/currencies.dart';
import '../model/enums.dart';
import '../utils/money.dart';

/// Affiche un montant dans la devise choisie (§5.1).
///
/// - avec [type] : signé et coloré (`+` vert pour un revenu, `−` rouge pour
///   une dépense, §2.3) ;
/// - sans [type] : neutre, rouge seulement si [amount] est négatif et que
///   [highlightNegative] est vrai.
class AmountText extends ConsumerWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.type,
    this.style,
    this.highlightNegative = true,
    this.color,
  });

  final int amount;
  final TransactionType? type;
  final TextStyle? style;
  final bool highlightNegative;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency =
        ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;
    final text = type == null
        ? formatMoney(amount, currency: currency)
        : formatSignedAmount(amount, type!, currency: currency);
    final resolvedColor =
        color ??
        switch (type) {
          TransactionType.income => KoloColors.positive,
          TransactionType.expense => KoloColors.negative,
          null when highlightNegative && amount < 0 => KoloColors.negative,
          null => null,
        };
    final base = (style ?? KoloTypography.amount).copyWith(
      fontFeatures: KoloTypography.tabular,
    );
    return Text(
      text,
      style: resolvedColor == null ? base : base.copyWith(color: resolvedColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}
