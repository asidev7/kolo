import 'package:intl/intl.dart';

import 'local_date.dart';

/// Formats de date en français. `initializeDateFormatting('fr')` est appelé
/// au démarrage (bootstrap) et dans les tests qui en dépendent.
abstract final class KoloDates {
  static String monthLabel(YearMonth month) {
    final label = DateFormat.yMMMM('fr')
        .format(DateTime(month.year, month.month));
    return _capitalize(label);
  }

  static String shortMonth(YearMonth month) => _capitalize(
    DateFormat.MMM('fr').format(DateTime(month.year, month.month)),
  );

  /// « Aujourd'hui », « Hier » ou « mardi 7 octobre ».
  static String dayHeader(LocalDate date, LocalDate today) {
    if (date == today) return "Aujourd'hui";
    if (date == today.addDays(-1)) return 'Hier';
    if (date == today.addDays(1)) return 'Demain';
    final pattern = date.year == today.year ? 'EEEE d MMMM' : 'EEEE d MMMM y';
    return _capitalize(DateFormat(pattern, 'fr').format(date.toDateTime()));
  }

  static String short(LocalDate date) =>
      DateFormat('d MMM y', 'fr').format(date.toDateTime());

  static String dateTime(DateTime value) =>
      DateFormat("d MMM y 'à' HH:mm", 'fr').format(value.toLocal());

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
