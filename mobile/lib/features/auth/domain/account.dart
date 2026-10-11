import 'package:meta/meta.dart';

import '../../../core/network/json_reader.dart';
import 'tokens.dart';

/// Compte connecté, tel que le renvoie l'API (`user` de la session).
@immutable
class Account {
  const Account({
    required this.id,
    required this.email,
    required this.firstName,
    required this.timezone,
  });

  factory Account.fromJson(Map<String, Object?> json) => Account(
    id: json.requireString('id'),
    email: json.requireString('email'),
    firstName: json.requireString('first_name'),
    timezone: json.optionalString('timezone') ?? defaultTimezone,
  );

  static const defaultTimezone = 'Africa/Porto-Novo';

  final String id;
  final String email;
  final String firstName;
  final String timezone;
}

/// Réponse complète de `register` / `login` / `changePassword` : le compte et
/// ses jetons.
@immutable
class AccountSession {
  const AccountSession({required this.account, required this.tokens});

  factory AccountSession.fromJson(Map<String, Object?> json) => AccountSession(
    account: Account.fromJson(json.requireMap('user')),
    tokens: Tokens.fromJson(json),
  );

  final Account account;
  final Tokens tokens;
}
