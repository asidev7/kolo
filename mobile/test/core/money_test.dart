import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/constants/currencies.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/money.dart';

void main() {
  group('formatMoney (XOF)', () {
    test('1500 → 1 500 F CFA avec espaces insécables', () {
      expect(formatMoney(1500), '1 500 F CFA');
    });

    test('valeurs limites', () {
      expect(formatMoney(0), '0 F CFA');
      expect(formatMoney(999), '999 F CFA');
      expect(formatMoney(1000), '1 000 F CFA');
      expect(formatMoney(kMaxAmount), '999 999 999 999 F CFA');
    });

    test('négatif avec le vrai signe moins', () {
      expect(formatMoney(-12500), '−12 500 F CFA');
    });

    test('aucune décimale pour XOF', () {
      expect(formatMoney(12500, showSymbol: false), '12 500');
    });

    test('devise à 2 décimales sans passer par un double', () {
      const eur = Currency(code: 'EUR', minorUnit: 2, symbol: '€', name: 'Euro');
      expect(formatMoney(123456, currency: eur), '1 234,56 €');
      expect(formatMoney(5, currency: eur), '0,05 €');
    });
  });

  test('formatSignedAmount : + pour un revenu, − pour une dépense', () {
    expect(formatSignedAmount(1500, TransactionType.income), '+1 500 F CFA');
    expect(formatSignedAmount(1500, TransactionType.expense), '−1 500 F CFA');
  });

  group('parseAmountInput', () {
    test('accepte les séparateurs de milliers usuels', () {
      expect(parseAmountInput('12 500'), 12500);
      expect(parseAmountInput('12 500'), 12500);
      expect(parseAmountInput('12 500'), 12500);
      expect(parseAmountInput('12.500'), 12500);
      expect(parseAmountInput('  1500 '), 1500);
    });

    test('refuse le vide et les caractères non numériques', () {
      expect(parseAmountInput(''), isNull);
      expect(parseAmountInput('   '), isNull);
      expect(parseAmountInput('-50'), isNull);
      expect(parseAmountInput('12a'), isNull);
      expect(parseAmountInput('12,5'), isNull);
    });

    test('0 est lu (la validation le refusera)', () {
      expect(parseAmountInput('0'), 0);
    });

    test(
      'très grand nombre : jamais de dépassement, toujours hors plafond',
      () {
        expect(
          parseAmountInput('99999999999999999999999'),
          greaterThan(kMaxAmount),
        );
        expect(parseAmountInput('1000000000000'), greaterThan(kMaxAmount));
      },
    );
  });

  group('parseAmountInput (devise à 2 décimales)', () {
    const eur = Currency(code: 'EUR', minorUnit: 2, symbol: '€', name: 'Euro');

    test('virgule et point sont des séparateurs décimaux', () {
      expect(parseAmountInput('12,5', currency: eur), 1250);
      expect(parseAmountInput('12.5', currency: eur), 1250);
      expect(parseAmountInput('12,50', currency: eur), 1250);
    });

    test('entier sans décimale = unités entières', () {
      expect(parseAmountInput('1250', currency: eur), 125000);
      expect(parseAmountInput('1 250', currency: eur), 125000);
    });

    test('refuse trop de décimales ou entrée invalide', () {
      expect(parseAmountInput('12,505', currency: eur), isNull);
      expect(parseAmountInput('abc', currency: eur), isNull);
      expect(parseAmountInput('', currency: eur), isNull);
    });

    test('zéro et petites valeurs', () {
      expect(parseAmountInput('0', currency: eur), 0);
      expect(parseAmountInput('0,05', currency: eur), 5);
    });
  });
}
