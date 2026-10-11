/// Table de référence des devises (§5.1).
///
/// `minorUnit` = nombre de décimales usuelles. Le montant stocké est toujours
/// un entier exprimé dans la plus petite unité : pour XOF (0 décimale),
/// 1 unité stockée = 1 franc CFA ; pour EUR (2 décimales), 1 unité = 1 centime.
/// Une nouvelle devise s'ajoute ici sans changer le schéma.
class Currency {
  const Currency({
    required this.code,
    required this.minorUnit,
    required this.symbol,
    required this.name,
  });

  final String code;
  final int minorUnit;
  final String symbol;

  /// Nom affiché dans le sélecteur de devise (ex. « Euro »).
  final String name;
}

abstract final class Currencies {
  static const xof = Currency(
    code: 'XOF',
    minorUnit: 0,
    symbol: 'F CFA',
    name: 'Franc CFA (UEMOA)',
  );
  static const eur = Currency(
    code: 'EUR',
    minorUnit: 2,
    symbol: '€',
    name: 'Euro',
  );
  static const usd = Currency(
    code: 'USD',
    minorUnit: 2,
    symbol: r'$',
    name: 'Dollar américain',
  );
  static const ngn = Currency(
    code: 'NGN',
    minorUnit: 2,
    symbol: '₦',
    name: 'Naira',
  );
  static const gbp = Currency(
    code: 'GBP',
    minorUnit: 2,
    symbol: '£',
    name: 'Livre sterling',
  );
  static const ghs = Currency(
    code: 'GHS',
    minorUnit: 2,
    symbol: '₵',
    name: 'Cedi ghanéen',
  );
  static const kes = Currency(
    code: 'KES',
    minorUnit: 2,
    symbol: 'KSh',
    name: 'Shilling kényan',
  );
  static const zar = Currency(
    code: 'ZAR',
    minorUnit: 2,
    symbol: 'R',
    name: 'Rand sud-africain',
  );
  static const cad = Currency(
    code: 'CAD',
    minorUnit: 2,
    symbol: 'CA\$',
    name: 'Dollar canadien',
  );
  static const mad = Currency(
    code: 'MAD',
    minorUnit: 2,
    symbol: 'DH',
    name: 'Dirham marocain',
  );
  static const cdf = Currency(
    code: 'CDF',
    minorUnit: 2,
    symbol: 'FC',
    name: 'Franc congolais',
  );

  /// Devises proposées au choix, la devise par défaut en premier.
  static const List<Currency> all = [
    xof,
    eur,
    usd,
    ngn,
    gbp,
    ghs,
    kes,
    zar,
    cad,
    mad,
    cdf,
  ];

  static final Map<String, Currency> byCode = {
    for (final c in all) c.code: c,
  };

  /// Devise utilisée tant que l'utilisateur n'en a pas choisi une.
  static const Currency defaultCurrency = xof;

  static Currency of(String code) => byCode[code] ?? xof;
}

/// Plafond de sécurité d'un montant saisi (§3.E).
const int kMaxAmount = 999999999999;

/// Longueur maximale d'une note (§3.E).
const int kMaxNoteLength = 140;
