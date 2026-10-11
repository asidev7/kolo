import 'package:meta/meta.dart';

enum SessionMode {
  /// Aucun choix encore fait (premier lancement après l'onboarding).
  none,

  /// « Commencer sans compte » : données uniquement sur ce téléphone.
  local,

  /// Compte connecté : données sauvegardées et synchronisées.
  account,
}

/// État de session lu depuis la base locale au démarrage.
@immutable
class Session {
  const Session({
    required this.onboardingSeen,
    required this.mode,
    this.userId,
    this.displayName,
    this.email,
  });

  static const initial = Session(onboardingSeen: false, mode: SessionMode.none);

  final bool onboardingSeen;
  final SessionMode mode;
  final String? userId;
  final String? displayName;
  final String? email;

  bool get isLocal => mode == SessionMode.local;

  bool get isAccount => mode == SessionMode.account && userId != null;

  bool get hasChosenMode => mode != SessionMode.none;

  /// Propriétaire des données consultées : `null` = profil local.
  String? get ownerId => isAccount ? userId : null;

  Session copyWith({
    bool? onboardingSeen,
    SessionMode? mode,
    String? Function()? userId,
    String? Function()? displayName,
    String? Function()? email,
  }) => Session(
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    mode: mode ?? this.mode,
    userId: userId != null ? userId() : this.userId,
    displayName: displayName != null ? displayName() : this.displayName,
    email: email != null ? email() : this.email,
  );

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.onboardingSeen == onboardingSeen &&
      other.mode == mode &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.email == email;

  @override
  int get hashCode =>
      Object.hash(onboardingSeen, mode, userId, displayName, email);
}
