import '../constants/currencies.dart';
import '../model/enums.dart';

/// Espace insécable : séparateur de milliers et avant le symbole (§2.3),
/// pour qu'un montant ne soit jamais coupé en fin de ligne.
const String nbsp = ' ';

/// Vrai signe moins typographique (U+2212), plus lisible que le tiret.
const String minusSign = '−';

/// Groupe les chiffres par milliers : `1500` → `1 500`.
String groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(nbsp);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formate un montant entier : `1500` → `1 500 F CFA`.
///
/// XOF n'a pas de décimale (§5.1). Le code est prêt pour une devise à
/// `minorUnit > 0`, sans jamais passer par un `double`.
String formatMoney(
  int amount, {
  Currency currency = Currencies.xof,
  bool showSymbol = true,
}) {
  final negative = amount < 0;
  final abs = amount.abs();
  String number;
  if (currency.minorUnit == 0) {
    number = groupThousands(abs);
  } else {
    var divisor = 1;
    for (var i = 0; i < currency.minorUnit; i++) {
      divisor *= 10;
    }
    final units = groupThousands(abs ~/ divisor);
    final minor = (abs % divisor).toString().padLeft(currency.minorUnit, '0');
    number = '$units,$minor';
  }
  final symbol = showSymbol
      ? '$nbsp${currency.symbol.replaceAll(' ', nbsp)}'
      : '';
  return '${negative ? minusSign : ''}$number$symbol';
}

/// Montant d'une opération avec son signe : `+1 500 F CFA` pour un revenu,
/// `−1 500 F CFA` pour une dépense (§2.3).
String formatSignedAmount(
  int amount,
  TransactionType type, {
  Currency currency = Currencies.xof,
}) {
  final sign = type == TransactionType.income ? '+' : minusSign;
  return '$sign${formatMoney(amount.abs(), currency: currency)}';
}

/// Lit une saisie utilisateur (« 12 500 », « 12.500 », « 12500 ») en entier.
///
/// Retourne `null` si la saisie est vide ou contient autre chose que des
/// chiffres et des séparateurs de milliers. Ne lève jamais d'exception.
int? parseAmountInput(String input, {Currency currency = Currencies.xof}) {
  if (currency.minorUnit == 0) {
    // Devise sans décimale : points et espaces sont des séparateurs de
    // milliers. « 12.500 » → 12 500 unités.
    final cleaned = input.replaceAll(RegExp('[\\s.  ]'), '');
    if (cleaned.isEmpty || !RegExp(r'^\d+$').hasMatch(cleaned)) return null;
    // Au-delà de 15 chiffres, on dépasse de toute façon le plafond : on évite
    // un dépassement d'entier en renvoyant une valeur hors plafond.
    if (cleaned.length > 15) return kMaxAmount + 1;
    return int.parse(cleaned);
  }
  // Devise à décimales : la virgule ou le point sépare les unités des
  // centimes. « 12,5 » → 1250 ; « 1 250 » → 125000.
  final cleaned = input.replaceAll(RegExp('[\\s  ]'), '');
  final match = RegExp(r'^(\d+)(?:[.,](\d*))?$').firstMatch(cleaned);
  if (match == null) return null;
  final units = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (fraction.length > currency.minorUnit) return null;
  final combined = units + fraction.padRight(currency.minorUnit, '0');
  if (combined.length > 15) return kMaxAmount + 1;
  return int.parse(combined);
}
