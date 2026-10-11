import '../../../core/errors/failures.dart';
import '../../../core/network/auth_interceptor.dart';
import 'auth_api.dart';
import 'token_store.dart';

/// Cycle de vie des jetons côté client : lecture pour chaque requête et
/// renouvellement **un seul à la fois**.
///
/// Un seul rafraîchissement concurrent : le serveur met l'ancien jeton en
/// liste noire, donc deux appels parallèles avec le même jeton font échouer le
/// second (docs/API.md). Le `Future` partagé garantit que tous les appelants
/// attendent le même renouvellement.
class TokenRefresher {
  TokenRefresher(this._api, this._store);

  final AuthApi _api;
  final TokenStore _store;

  Future<RefreshOutcome>? _pending;

  /// Jeton d'accès courant, pour l'en-tête `Authorization`.
  Future<String?> accessToken() async => (await _store.read())?.access;

  Future<RefreshOutcome> refresh() {
    final pending = _pending;
    if (pending != null) return pending;
    final future = _run();
    _pending = future;
    return future;
  }

  Future<RefreshOutcome> _run() async {
    try {
      final tokens = await _store.read();
      if (tokens == null) return const RefreshRefused();
      try {
        final renewed = await _api.refresh(tokens.refresh);
        await _store.write(renewed);
        return Refreshed(renewed.access);
      } on ApiFailure catch (failure) {
        // 401 : le jeton de rafraîchissement est mort (expiré, déjà utilisé,
        // révoqué). Toute autre réponse (5xx, réseau) est réessayable.
        if (failure.statusCode == 401) {
          await _store.clear();
          return const RefreshRefused();
        }
        rethrow;
      }
    } finally {
      _pending = null;
    }
  }
}
