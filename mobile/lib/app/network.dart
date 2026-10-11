import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/network/auth_interceptor.dart';
import '../core/providers/core_providers.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/token_refresher.dart';
import '../features/auth/data/token_store.dart';

/// Câblage de la pile HTTP — racine de composition.
///
/// Deux clients distincts, et c'est volontaire :
/// - [plainApiClientProvider] **sans** intercepteur sert au renouvellement de
///   jeton (un intercepteur qui se rejoue lui-même bouclerait) ;
/// - [apiClientProvider] ajoute `Authorization` et le nouvel essai après
///   renouvellement, pour tous les appels métier (`auth`, `sync`).
///
/// Tout est ici plutôt que dans `core/` parce que le socle réseau du noyau ne
/// doit pas connaître les jetons (couche `features/auth`).

final plainApiClientProvider = Provider<ApiClient>(
  (ref) => plainApiClient(ref.watch(appConfigProvider).apiBaseUrl),
);

/// Client **sans** intercepteur : un renouvellement de jeton ne doit pas
/// pouvoir se rejouer lui-même.
ApiClient plainApiClient(String baseUrl) => ApiClient(baseUrl: baseUrl);

/// Client des appels métier : `Authorization`, et un nouvel essai après
/// renouvellement du jeton.
ApiClient buildApiClient({
  required String baseUrl,
  required TokenRefresher refresher,
}) => ApiClient(
  baseUrl: baseUrl,
  interceptor: (dio) => AuthInterceptor(
    dio: dio,
    readAccessToken: refresher.accessToken,
    refresh: refresher.refresh,
  ),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// API d'authentification sur le client **nu** (renouvellement de jeton).
final plainAuthApiProvider = Provider<AuthApi>(
  (ref) => HttpAuthApi(ref.watch(plainApiClientProvider)),
);

final tokenRefresherProvider = Provider<TokenRefresher>(
  (ref) => TokenRefresher(
    ref.watch(plainAuthApiProvider),
    ref.watch(tokenStoreProvider),
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => buildApiClient(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    refresher: ref.watch(tokenRefresherProvider),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => HttpAuthApi(ref.watch(apiClientProvider)),
);
