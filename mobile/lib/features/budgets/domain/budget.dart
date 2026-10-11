import 'package:meta/meta.dart';

import '../../../core/utils/local_date.dart';

/// Plafond mensuel global (§5.5).
@immutable
class Budget {
  const Budget({
    required this.id,
    required this.period,
    required this.limitAmount,
    required this.alertThresholds,
  });

  final String id;

  /// Mois de définition ; s'applique aussi aux mois suivants tant qu'aucun
  /// autre budget n'est défini (reconduction, §3.I).
  final YearMonth period;
  final int limitAmount;
  final List<int> alertThresholds;

  static const List<int> defaultThresholds = [80, 100];
}

enum BudgetLevel {
  /// Aucun plafond défini (ou plafond à 0).
  none,
  healthy,

  /// Premier seuil d'alerte atteint.
  warning,

  /// 100 % atteint ou dépassé.
  exceeded,
}

/// Situation du budget d'un mois (§6). Valeurs calculées sans `double`.
@immutable
class BudgetStatus {
  const BudgetStatus._({
    required this.limit,
    required this.spent,
    required this.remaining,
    required this.percent,
    required this.level,
  });

  /// Calcule l'état d'un budget.
  ///
  /// - restant = plafond − dépenses (peut être négatif) ;
  /// - % consommé = dépenses × 100 / plafond, **arrondi à l'unité
  ///   inférieure** ; `null` si le plafond est nul (« Aucun budget défini »).
  factory BudgetStatus.compute({
    required int? limit,
    required int spent,
    List<int> thresholds = Budget.defaultThresholds,
  }) {
    if (limit == null || limit <= 0) {
      return BudgetStatus._(
        limit: limit ?? 0,
        spent: spent,
        remaining: -spent,
        percent: null,
        level: BudgetLevel.none,
      );
    }
    final percent = (spent * 100) ~/ limit;
    final warningAt = thresholds
        .where((t) => t < 100)
        .fold<int?>(null, (min, t) => min == null || t < min ? t : min);
    final level = percent >= 100
        ? BudgetLevel.exceeded
        : warningAt != null && percent >= warningAt
        ? BudgetLevel.warning
        : BudgetLevel.healthy;
    return BudgetStatus._(
      limit: limit,
      spent: spent,
      remaining: limit - spent,
      percent: percent,
      level: level,
    );
  }

  final int limit;
  final int spent;
  final int remaining;
  final int? percent;
  final BudgetLevel level;

  bool get hasBudget => percent != null;

  /// Fraction pour une barre de progression, bornée à [0, 1]. Usage
  /// strictement visuel : aucun calcul financier ne passe par ce `double`.
  double get progress => percent == null ? 0 : (percent!.clamp(0, 100) / 100);
}

/// Seuils franchis par [percent] et pas encore notifiés (§3.I).
List<int> thresholdsToNotify({
  required int? percent,
  required List<int> thresholds,
  required Set<int> alreadyNotified,
}) {
  if (percent == null) return const [];
  return [
    for (final t in (thresholds.toSet().toList()..sort()))
      if (percent >= t && !alreadyNotified.contains(t)) t,
  ];
}
