import 'package:meta/meta.dart';

/// Date métier sans heure ni fuseau (`occurred_on`, §5.3).
///
/// Stockée en `YYYY-MM-DD` : l'ordre lexicographique est l'ordre
/// chronologique, ce qui permet de filtrer un mois par simple comparaison de
/// chaînes, sans conversion de fuseau.
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day)
    : assert(month >= 1 && month <= 12),
      assert(day >= 1 && day <= 31);

  factory LocalDate.fromDateTime(DateTime dt) =>
      LocalDate(dt.year, dt.month, dt.day);

  /// Analyse `YYYY-MM-DD`. Lève [FormatException] si le format est invalide.
  factory LocalDate.parse(String iso) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (match == null) throw FormatException('Date invalide', iso);
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    // Rejette les dates impossibles (13e mois, 31 février…).
    final probe = DateTime(year, month, day);
    if (month < 1 || month > 12 || probe.month != month || probe.day != day) {
      throw FormatException('Date invalide', iso);
    }
    return LocalDate(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  /// Minuit local, uniquement pour l'affichage et l'arithmétique de jours.
  DateTime toDateTime() => DateTime(year, month, day);

  LocalDate addDays(int days) =>
      LocalDate.fromDateTime(DateTime(year, month, day + days));

  YearMonth get yearMonth => YearMonth(year, month);

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}-${_two(day)}';

  @override
  int compareTo(LocalDate other) => toIso().compareTo(other.toIso());

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// Mois calendaire (`period` d'un budget, sélecteur de période).
@immutable
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month);

  factory YearMonth.fromDateTime(DateTime dt) => YearMonth(dt.year, dt.month);

  factory YearMonth.parse(String iso) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(iso);
    if (match == null) throw FormatException('Période invalide', iso);
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) throw FormatException('Période invalide', iso);
    return YearMonth(int.parse(match.group(1)!), month);
  }

  final int year;
  final int month;

  LocalDate get firstDay => LocalDate(year, month, 1);

  LocalDate get lastDay => LocalDate.fromDateTime(DateTime(year, month + 1, 0));

  int get dayCount => lastDay.day;

  YearMonth addMonths(int months) {
    final index = year * 12 + (month - 1) + months;
    return YearMonth(index ~/ 12, index % 12 + 1);
  }

  bool contains(LocalDate date) => date.year == year && date.month == month;

  String toIso() => '${year.toString().padLeft(4, '0')}-${_two(month)}';

  @override
  int compareTo(YearMonth other) => toIso().compareTo(other.toIso());

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => toIso();
}

String _two(int value) => value.toString().padLeft(2, '0');
