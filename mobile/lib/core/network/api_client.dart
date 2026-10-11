import 'package:dio/dio.dart';

import '../errors/failures.dart';

/// Socle HTTP de l'application : un seul endroit qui connaît Dio.
///
/// Il ne connaît **aucune route métier** : il se contente d'envoyer, de
/// décoder le JSON et de traduire toute panne en [Failure] présentable. Les
/// couches au-dessus (`AuthApi`, `SyncApi`) ne voient jamais de `DioException`.
class ApiClient {
  /// [baseUrl] : valeur de `--dart-define=API_BASE_URL`.
  ///
  /// [interceptor] reçoit le `Dio` interne (nécessaire à un intercepteur qui
  /// doit rejouer une requête après renouvellement du jeton).
  ApiClient({
    required this.baseUrl,
    Interceptor Function(Dio dio)? interceptor,
  }) {
    // L'API KOLO est montée sous `/api/v1` (backend/kolo/urls.py). `baseUrl`
    // reste l'**origine nue** fournie par `--dart-define=API_BASE_URL`
    // (ex. `https://api.asitechsolution.cloud`) : on ajoute ici le préfixe de
    // version pour que `/auth/register`, `/sync/push`, etc. résolvent vers les
    // bonnes routes, quel que soit le client (interactif, refresh, fond).
    // Sans backend (mode local), `baseUrl` est vide : on ne le préfixe pas,
    // sinon Dio refuserait un `baseUrl` « /api/v1 » sans hôte.
    final versioned = baseUrl.isEmpty
        ? baseUrl
        : '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/api/v1';
    dio = Dio(
      BaseOptions(
        baseUrl: versioned,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 10),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    final extra = interceptor?.call(dio);
    if (extra != null) dio.interceptors.add(extra);
  }

  final String baseUrl;

  /// `Dio` sous-jacent, exposé pour les intercepteurs et les tests.
  late final Dio dio;

  Future<Map<String, Object?>> getJson(
    String path, {
    Map<String, Object?>? query,
  }) => _send(() => dio.get<Object?>(path, queryParameters: query));

  Future<Map<String, Object?>> postJson(String path, {Object? data}) =>
      _send(() => dio.post<Object?>(path, data: data));

  Future<Map<String, Object?>> patchJson(String path, {Object? data}) =>
      _send(() => dio.patch<Object?>(path, data: data));

  /// Requête dont la réponse n'a pas de corps (`204`), comme la déconnexion.
  Future<void> postEmpty(String path, {Object? data}) async {
    await _send(() => dio.post<Object?>(path, data: data));
  }

  Future<Map<String, Object?>> _send(
    Future<Response<Object?>> Function() request,
  ) async {
    try {
      return asJsonObject((await request()).data);
    } on DioException catch (error) {
      throw failureFrom(error);
    }
  }
}

/// Corps JSON attendu : un objet. Toute autre forme est une réponse
/// inexploitable, jamais un plantage de l'application.
Map<String, Object?> asJsonObject(Object? data) {
  if (data == null) return const {};
  if (data is Map<Object?, Object?>) {
    return {for (final entry in data.entries) '${entry.key}': entry.value};
  }
  throw const ApiFailure(
    code: 'invalid_response',
    message: 'Réponse inattendue du serveur.',
  );
}

/// Traduit une panne Dio en [Failure].
///
/// Un [Failure] déjà placé dans `error.error` (par l'intercepteur d'auth) est
/// renvoyé tel quel : c'est ce qui permet de remonter une session expirée au
/// lieu d'un banal 401.
Failure failureFrom(DioException error) {
  final wrapped = error.error;
  if (wrapped is Failure) return wrapped;

  final response = error.response;
  // Aucune réponse : réseau coupé, DNS, délai dépassé, serveur injoignable.
  if (response == null) return const RetryableFailure();

  final status = response.statusCode ?? 0;
  var code = 'http_$status';
  var message = _defaultMessageFor(status);
  var fields = const <String, String>{};

  final body = response.data;
  if (body is Map<Object?, Object?>) {
    final details = body['error'];
    if (details is Map<Object?, Object?>) {
      final rawCode = details['code'];
      if (rawCode is String && rawCode.isNotEmpty) code = rawCode;
      final rawMessage = details['message'];
      if (rawMessage is String && rawMessage.isNotEmpty) message = rawMessage;
      fields = _fieldsFrom(details['fields']);
    }
  }

  if (status >= 500 || status == 429 || status == 408) {
    return RetryableFailure(message);
  }
  return ApiFailure(
    code: code,
    message: message,
    statusCode: status,
    fields: fields,
  );
}

/// Attache un [Failure] à une `DioException` pour qu'il traverse les
/// intercepteurs et `failureFrom` sans être réinterprété.
DioException dioExceptionWith(DioException source, Failure failure) =>
    DioException(
      requestOptions: source.requestOptions,
      response: source.response,
      type: source.type,
      error: failure,
    );

Map<String, String> _fieldsFrom(Object? raw) {
  if (raw is! Map<Object?, Object?>) return const {};
  final fields = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final value = entry.value;
    // L'API renvoie tantôt une chaîne, tantôt une liste de messages.
    final message = switch (value) {
      final String s when s.isNotEmpty => s,
      final List<Object?> list => list.whereType<String>().join(' '),
      _ => null,
    };
    if (message != null && message.isNotEmpty) fields[key] = message;
  }
  return fields;
}

/// Repli quand le serveur ne fournit pas de `message` exploitable.
String _defaultMessageFor(int status) => switch (status) {
  400 || 422 => 'Certaines informations ont été refusées par le serveur.',
  401 => 'Identifiants incorrects ou session expirée.',
  403 => "Tu n'as pas accès à cette information.",
  404 => "Cette information n'existe plus sur le serveur.",
  409 => 'Cet enregistrement existe déjà.',
  429 => 'Trop de tentatives. Réessaie dans un instant.',
  _ => 'Le serveur a renvoyé une erreur inattendue.',
};
