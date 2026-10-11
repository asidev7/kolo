import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/features/budgets/domain/budget.dart';
import 'package:kolo/features/transactions/domain/finance.dart';

void main() {
  group('BudgetStatus', () {
    test('restant et pourcentage arrondi à l\'unité inférieure', () {
      final s = BudgetStatus.compute(limit: 30000, spent: 10001);
      expect(s.remaining, 19999);
      expect(s.percent, 33);
      expect(s.level, BudgetLevel.healthy);
    });

    test('79,99 % reste sain ; 80 % déclenche l\'alerte', () {
      expect(
        BudgetStatus.compute(limit: 10000, spent: 7999).level,
        BudgetLevel.healthy,
      );
      expect(BudgetStatus.compute(limit: 10000, spent: 7999).percent, 79);
      expect(
        BudgetStatus.compute(limit: 10000, spent: 8000).level,
        BudgetLevel.warning,
      );
    });

    test('dépassement : restant négatif, niveau dépassé', () {
      final s = BudgetStatus.compute(limit: 10000, spent: 12500);
      expect(s.remaining, -2500);
      expect(s.percent, 125);
      expect(s.level, BudgetLevel.exceeded);
      expect(s.progress, 1.0);
    });

    test('plafond nul ou absent : « Aucun budget défini »', () {
      for (final limit in [null, 0]) {
        final s = BudgetStatus.compute(limit: limit, spent: 5000);
        expect(s.hasBudget, isFalse);
        expect(s.percent, isNull);
        expect(s.level, BudgetLevel.none);
      }
    });

    test('seuils personnalisés', () {
      final s = BudgetStatus.compute(
        limit: 1000,
        spent: 500,
        thresholds: [50, 100],
      );
      expect(s.level, BudgetLevel.warning);
    });
  });

  group('thresholdsToNotify', () {
    test('une seule fois par seuil', () {
      expect(
        thresholdsToNotify(
          percent: 85,
          thresholds: [80, 100],
          alreadyNotified: {},
        ),
        [80],
      );
      expect(
        thresholdsToNotify(
          percent: 85,
          thresholds: [80, 100],
          alreadyNotified: {80},
        ),
        isEmpty,
      );
      expect(
        thresholdsToNotify(
          percent: 130,
          thresholds: [100, 80],
          alreadyNotified: {},
        ),
        [80, 100],
      );
      expect(
        thresholdsToNotify(
          percent: null,
          thresholds: [80],
          alreadyNotified: {},
        ),
        isEmpty,
      );
    });
  });

  group('Finance', () {
    test('solde net = revenus − dépenses', () {
      expect(
        Finance.netBalance(const TypeTotals(income: 50000, expense: 62500)),
        -12500,
      );
      expect(Finance.netBalance(TypeTotals.zero), 0);
    });

    test('percentOf', () {
      expect(Finance.percentOf(1, 3), 33);
      expect(Finance.percentOf(5, 0), isNull);
    });

    test('cumulative', () {
      expect(Finance.cumulative({1: 100, 3: 50}, 4), [100, 100, 150, 150]);
    });
  });
}
