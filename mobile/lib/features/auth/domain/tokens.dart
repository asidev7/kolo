import 'package:meta/meta.dart';

import '../../../core/network/json_reader.dart';

/// Paire de jetons JWT renvoyée par `/auth/login`, `/auth/register` et
/// `/auth/refresh`.
///
/// **Jamais dans `app_settings`** : les jetons vivent dans le coffre sécurisé
/// du système (Keychain / Keystore), voir [TokenStore].
@immutable
class Tokens {
  const Tokens({required this.access, required this.refresh});

  factory Tokens.fromJson(Map<String, Object?> json) => Tokens(
    access: json.requireString('access'),
    refresh: json.requireString('refresh'),
  );

  /// Jeton d'accès, valable 15 minutes.
  final String access;

  /// Jeton de rafraîchissement, valable 30 jours, à rotation.
  final String refresh;

  @override
  bool operator ==(Object other) =>
      other is Tokens && other.access == access && other.refresh == refresh;

  @override
  int get hashCode => Object.hash(access, refresh);
}
