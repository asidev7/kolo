import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/kolo_colors.dart';
import '../../app/theme/kolo_typography.dart';
import '../constants/currencies.dart';
import '../utils/money.dart';

/// Formate la saisie en groupes de milliers pendant la frappe :
/// `12500` → `12 500`. N'accepte que des chiffres.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter();

  /// 13 chiffres suffisent à dépasser le plafond et donc à l'afficher en
  /// erreur, sans laisser saisir des valeurs absurdes.
  static const int maxDigits = 13;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp('^0+(?=\\d)'), '');
    if (digits.length > maxDigits) return oldValue;
    if (digits.isEmpty) return const TextEditingValue();

    // Position du curseur exprimée en nombre de chiffres à sa gauche.
    final cursor = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCursor = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp(r'\D'), '')
        .length;

    final formatted = groupThousands(int.parse(digits));
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[offset])) seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Formate la saisie d'un montant décimal pendant la frappe :
/// `1250` → `1 250`, `12,5` → `12,5`. Accepte au plus [maxDecimals]
/// décimales et un seul séparateur (`,` ou `.`).
class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter(this.maxDecimals);

  final int maxDecimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    final dot = text.indexOf('.');
    var intPart = dot < 0 ? text : text.substring(0, dot);
    var fraction = dot < 0 ? '' : text.substring(dot + 1);

    intPart = intPart.replaceAll(RegExp(r'[^0-9]'), '');
    fraction = fraction.replaceAll(RegExp(r'[^0-9]'), '');
    if (fraction.length > maxDecimals) {
      fraction = fraction.substring(0, maxDecimals);
    }
    intPart = intPart.replaceFirst(RegExp('^0+(?=\\d)'), '');
    if (intPart.length > 13) return oldValue;

    final grouped = intPart.isEmpty ? '0' : groupThousands(int.parse(intPart));
    final result = dot < 0 ? grouped : '$grouped.$fraction';
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

/// Champ montant : clavier numérique, gros chiffres, devise affichée (§3.E).
/// Sans décimale (XOF) ou avec décimale (EUR, USD…) selon la devise choisie.
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    super.key,
    this.color,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
    this.currency = Currencies.xof,
  });

  final TextEditingController controller;
  final Color? color;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final style = KoloTypography.display.copyWith(
      color: color ?? KoloColors.textPrimary,
    );
    return Semantics(
      label: 'Montant en ${currency.symbol}',
      textField: true,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          if (currency.minorUnit == 0)
            const ThousandsInputFormatter()
          else
            DecimalInputFormatter(currency.minorUnit),
        ],
        onChanged: onChanged,
        style: style,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: style.copyWith(color: KoloColors.border),
          suffixText: currency.symbol,
          suffixStyle: KoloTypography.subtitle.copyWith(
            color: KoloColors.textSecondary,
          ),
          errorText: errorText,
          errorMaxLines: 2,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      ),
    );
  }
}
