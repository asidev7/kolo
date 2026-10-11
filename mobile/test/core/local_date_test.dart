import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/utils/local_date.dart';
import 'package:kolo/core/utils/text_normalize.dart';

void main() {
  group('LocalDate', () {
    test('aller-retour ISO', () {
      expect(LocalDate.parse('2026-02-28').toIso(), '2026-02-28');
      expect(const LocalDate(2026, 1, 5).toIso(), '2026-01-05');
    });

    test('refuse les dates impossibles', () {
      expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
      expect(() => LocalDate.parse('2026-13-01'), throwsFormatException);
      expect(() => LocalDate.parse('09/10/2026'), throwsFormatException);
    });

    test('addDays franchit les mois et les années', () {
      expect(
        const LocalDate(2026, 12, 31).addDays(1),
        const LocalDate(2027, 1, 1),
      );
      expect(
        const LocalDate(2026, 3, 1).addDays(-1),
        const LocalDate(2026, 2, 28),
      );
    });

    test("l'ordre ISO est l'ordre chronologique", () {
      expect(
        const LocalDate(2026, 9, 30).isBefore(const LocalDate(2026, 10, 1)),
        isTrue,
      );
    });
  });

  group('YearMonth', () {
    test('bornes du mois, y compris février bissextile', () {
      expect(const YearMonth(2028, 2).lastDay, const LocalDate(2028, 2, 29));
      expect(const YearMonth(2026, 2).dayCount, 28);
      expect(const YearMonth(2026, 10).firstDay.toIso(), '2026-10-01');
    });

    test('addMonths traverse les années', () {
      expect(const YearMonth(2026, 1).addMonths(-1), const YearMonth(2025, 12));
      expect(const YearMonth(2026, 11).addMonths(3), const YearMonth(2027, 2));
      expect(const YearMonth(2026, 10).addMonths(-5), const YearMonth(2026, 5));
    });

    test('parse', () {
      expect(YearMonth.parse('2026-10'), const YearMonth(2026, 10));
      expect(() => YearMonth.parse('2026-13'), throwsFormatException);
    });
  });

  group('normalizeForSearch', () {
    test('insensible à la casse et aux accents', () {
      expect(normalizeForSearch('  Zémidjan  ÉCOLE '), 'zemidjan ecole');
      expect(normalizeForSearch('Œuvre'), 'oeuvre');
    });

    test('escapeLike neutralise les jokers', () {
      expect(escapeLike(r'50%_a\b'), r'50\%\_a\\b');
    });
  });
}
