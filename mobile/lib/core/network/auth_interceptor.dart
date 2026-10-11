import 'package:dio/dio.dart';

import '../errors/failures.dart';
import 'api_client.dart';

/// Résultat d'une tentative de renouvellement de jeton.
sealed class RefreshOutcome {
  const RefreshOutcome();
}

/// Nouveau jeton d'accès obtenu.
final class Refreshed extends RefreshOutcome {
  const Refreshed(this.access);

  final String access;
}

/// Le serveur a refusé le jeton de rafraîchissement : la session est close et
/// l'utilisateur doit se reconnecter.
final class RefreshRefused extends RefreshOutcome {
  const RefreshRefused();
}

/// Ajoute `Authorization: Bearer` et rejoue **une** fois une requête refusée
/// avec un jeton neuf (§6).
///
/// Le renouvellement lui-même est délégué : c'est la couche qui possède les
/// jetons qui garantit qu'un seul rafraîchissement est en vol à la fois (deux
/// rafraîchissements concurrents du même jeton font échouer le second,
/// docs/API.md).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.readAccessToken,
    required this.refresh,
    this.skipRefreshPaths = const {
      '/auth/login',
      '/auth/register',
      '/auth/refresh',
      '/auth/password/',
    },
  });

  /// Utilisé pour rejouer la requête avec le nouveau jeton.
  final Dio dio;

  final Future<String?> Function() readAccessToken;

  /// Renouvelle le jeton. Peut lever [RetryableFailure] si le réseau est en
  /// cause : ce n'est **pas** une session expirée.
  final Future<RefreshOutcome> Function() refresh;

  /// Chemins pour lesquels un 401 est une réponse métier (mot de passe
  /// incorrect, code périmé), jamais un jeton à renouveler.
  final Set<String> skipRefreshPaths;

  static const _retriedKey = 'auth.retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!options.headers.containsKey('Authorization')) {
      final token = await readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final alreadyRetried = options.extra[_retriedKey] == true;
    final isAuthFailure = err.response?.statusCode == 401;

    if (!isAuthFailure || alreadyRetried || _skipsRefresh(options.path)) {
      handler.next(err);
      return;
    }

    final RefreshOutcome outcome;
    try {
      outcome = await refresh();
    } on Failure catch (failure) {
      // Réseau en cause : on laisse le moteur réessayer plus tard.
      handler.reject(dioExceptionWith(err, failure));
      return;
    }

    switch (outcome) {
      case RefreshRefused():
        handler.reject(dioExceptionWith(err, const SessionExpiredFailure()));
        return;
      case Refreshed(:final access):
        options
          ..extra[_retriedKey] = true
          ..headers['Authorization'] = 'Bearer $access';
        try {
          handler.resolve(await dio.fetch<Object?>(options));
        } on DioException catch (retryError) {
          handler.next(retryError);
        }
    }
  }

  bool _skipsRefresh(String path) =>
      skipRefreshPaths.any((prefix) => path.startsWith(prefix));
}
