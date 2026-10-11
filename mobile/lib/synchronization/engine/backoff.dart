/// Recul exponentiel des tentatives de synchronisation (§6).
///
/// Fonction pure, donc testable sans horloge ni réseau : le moteur ne fait que
/// lui passer le nombre de tentatives déjà effectuées.
///
/// 5 s → 15 s → 1 min → 5 min → 15 min → 1 h, puis plafond à 1 h. Le jitter
/// (jusqu'à +10 %) évite que tous les téléphones d'un même réseau, remis en
/// ligne ensemble, frappent le serveur à la même seconde.
library;

import 'dart:math';

/// Palier du recul, du plus court au plus long.
const List<Duration> syncBackoffSteps = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(hours: 1),
];

/// Part d'aléa ajoutée au palier.
const double syncBackoffJitterRatio = 0.1;

/// Délai à observer après [attempts] tentatives déjà effectuées.
///
/// [random] doit être dans `[0, 1)` (valeur de `Random.nextDouble`) ; à 0, le
/// délai est exactement le palier, ce qui rend les tests déterministes.
Duration backoffDelay(int attempts, {double random = 0}) {
  final index = (attempts < 1 ? 1 : attempts).clamp(1, syncBackoffSteps.length);
  final base = syncBackoffSteps[index - 1].inMilliseconds;
  final extra = (base * syncBackoffJitterRatio * random.clamp(0.0, 1.0))
      .round();
  return Duration(milliseconds: base + extra);
}

/// Instant de la prochaine tentative, écrit dans `outbox.next_attempt_at`.
DateTime nextAttemptAt(DateTime now, int attempts, {double random = 0}) =>
    now.add(backoffDelay(attempts, random: random));

/// Source d'aléa du moteur, injectable pour des tests déterministes.
typedef JitterSource = double Function();

double defaultJitter() => Random().nextDouble();
