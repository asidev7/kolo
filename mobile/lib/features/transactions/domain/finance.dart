import '../../../core/model/totals.dart';

export '../../../core/model/totals.dart';

/// Calculs financiers purs (§6). Entiers uniquement.
abstract final class Finance {
  /// Solde net enregistré = Σ revenus − Σ dépenses (non supprimés).
  ///
  /// **Ce n'est pas un solde bancaire** : l'interface l'appelle toujours
  /// « Solde net enregistré ».
  static int netBalance(TypeTotals totals) => totals.income - totals.expense;

  /// Pourcentage entier (arrondi inférieur) de [part] dans [total] ; `null`
  /// si [total] est nul.
  static int? percentOf(int part, int total) =>
      total <= 0 ? null : (part * 100) ~/ total;

  /// Cumul jour par jour des dépenses d'un mois de [dayCount] jours.
  /// [byDay] associe un numéro de jour (1..31) à la dépense du jour.
  static List<int> cumulative(Map<int, int> byDay, int dayCount) {
    final result = <int>[];
    var running = 0;
    for (var day = 1; day <= dayCount; day++) {
      running += byDay[day] ?? 0;
      result.add(running);
    }
    return result;
  }
}
