import 'package:meta/meta.dart';

/// Où en est le moteur, du point de vue de l'interface.
///
/// Volontairement pauvre : l'écran n'a pas besoin de savoir *pourquoi* un cycle
/// a échoué, seulement s'il tourne, s'il faut réessayer ou s'il y a un message
/// à montrer.
enum SyncPhase {
  /// Rien en cours.
  idle,

  /// Un cycle est en cours.
  running,
}

/// État courant du moteur, porté par `syncRunStateProvider`.
@immutable
class SyncRunState {
  const SyncRunState({this.phase = SyncPhase.idle, this.message});

  final SyncPhase phase;

  /// Message présentable du dernier échec, `null` si le dernier cycle a réussi.
  final String? message;

  bool get isRunning => phase == SyncPhase.running;

  @override
  bool operator ==(Object other) =>
      other is SyncRunState && other.phase == phase && other.message == message;

  @override
  int get hashCode => Object.hash(phase, message);
}
