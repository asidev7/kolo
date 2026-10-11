import '../../../core/network/api_client.dart';
import '../domain/account.dart';
import '../domain/tokens.dart';

/// Appels d'authentification (docs/API.md §Comptes).
///
/// Interface séparée de l'implémentation HTTP : les tests du moteur et des
/// écrans utilisent un faux serveur en mémoire, pas des `Mock` de Dio.
abstract interface class AuthApi {
  Future<AccountSession> register({
    required String email,
    required String password,
    required String firstName,
  });

  Future<AccountSession> login({
    required String email,
    required String password,
  });

  /// Échange un jeton de rafraîchissement contre une paire neuve.
  ///
  /// L'ancien jeton est mis en liste noire : deux appels concurrents avec le
  /// même jeton font échouer le second (d'où le « un seul refresh à la fois »
  /// de [TokenRefresher]).
  Future<Tokens> refresh(String refreshToken);

  Future<void> logout(String refreshToken);

  Future<Account> me();

  /// Toujours `202`, que le compte existe ou non (l'API ne le révèle pas).
  Future<void> forgotPassword(String email);

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Renvoie une session neuve ; les autres appareils sont déconnectés.
  Future<AccountSession> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

class HttpAuthApi implements AuthApi {
  HttpAuthApi(this._client);

  final ApiClient _client;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
    required String firstName,
  }) async => AccountSession.fromJson(
    await _client.postJson(
      '/auth/register',
      data: {'email': email, 'password': password, 'first_name': firstName},
    ),
  );

  @override
  Future<AccountSession> login({
    required String email,
    required String password,
  }) async => AccountSession.fromJson(
    await _client.postJson(
      '/auth/login',
      data: {'email': email, 'password': password},
    ),
  );

  @override
  Future<Tokens> refresh(String refreshToken) async => Tokens.fromJson(
    await _client.postJson('/auth/refresh', data: {'refresh': refreshToken}),
  );

  @override
  Future<void> logout(String refreshToken) =>
      _client.postEmpty('/auth/logout', data: {'refresh': refreshToken});

  @override
  Future<Account> me() async =>
      Account.fromJson(await _client.getJson('/auth/me'));

  @override
  Future<void> forgotPassword(String email) =>
      _client.postEmpty('/auth/password/forgot', data: {'email': email});

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) => _client.postEmpty(
    '/auth/password/reset',
    data: {'email': email, 'code': code, 'new_password': newPassword},
  );

  @override
  Future<AccountSession> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => AccountSession.fromJson(
    await _client.postJson(
      '/auth/password/change',
      data: {'current_password': currentPassword, 'new_password': newPassword},
    ),
  );
}
