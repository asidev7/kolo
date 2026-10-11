import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

import 'local_date.dart';

/// Horloge de l'application, injectable pour des tests déterministes
/// (§14.9).
class TimeSource {
  const TimeSource([this._clock = const Clock()]);

  final Clock _clock;

  /// Instant courant en UTC, **tronqué à la milliseconde** : les horodatages
  /// sont stockés en texte ISO-8601 et doivent garder un format fixe pour que
  /// l'ordre des chaînes reste l'ordre chronologique.
  DateTime nowUtc() => DateTime.fromMillisecondsSinceEpoch(
    _clock.now().millisecondsSinceEpoch,
    isUtc: true,
  );

  /// Date du jour dans le fuseau de l'appareil.
  ///
  /// Décision v1 : le fuseau de l'appareil fait foi pour « aujourd'hui »
  /// (voir docs/ARCHITECTURE.md, Décisions).
  LocalDate today() => LocalDate.fromDateTime(_clock.now().toLocal());

  YearMonth currentMonth() => today().yearMonth;
}

/// Générateur d'identifiants, injectable (§14.9).
typedef IdGenerator = String Function();

const Uuid _uuid = Uuid();

/// UUID v4 côté client.
String generateUuidV4() => _uuid.v4();
