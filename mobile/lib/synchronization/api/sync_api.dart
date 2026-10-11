import '../../core/errors/failures.dart';
import '../../core/network/api_client.dart';
import '../wire/sync_dto.dart';

/// Accès au point d'entrée `/sync/` (§4.4).
///
/// Interface séparée de l'implémentation HTTP (D32) : les tests du moteur
/// utilisent un faux serveur en mémoire qui applique les règles de SYNC.md §9,
/// pas un `Dio` simulé.
abstract interface class SyncApi {
  /// Envoie au plus 100 opérations. La réponse contient un résultat par
  /// opération, dans l'ordre reçu.
  Future<PushResponse> push({
    required String deviceId,
    required List<PushOperation> operations,
  });

  /// Récupère une page de changements.
  ///
  /// Lève [CursorResetRequired] sur `410` : le curseur local précède une purge
  /// et le moteur doit repartir de `cursor=0`.
  Future<PullPage> pull({required String cursor, required int limit});
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this._client);

  final ApiClient _client;

  @override
  Future<PushResponse> push({
    required String deviceId,
    required List<PushOperation> operations,
  }) async => PushResponse.fromJson(
    await _client.postJson(
      '/sync/push',
      data: {
        'device_id': deviceId,
        'operations': [for (final op in operations) op.toJson()],
      },
    ),
  );

  @override
  Future<PullPage> pull({required String cursor, required int limit}) async {
    try {
      return PullPage.fromJson(
        await _client.getJson(
          '/sync/pull',
          query: {'cursor': cursor, 'limit': limit},
        ),
      );
    } on ApiFailure catch (failure) {
      // `410 cursor_reset_required` n'est pas une panne : c'est une consigne
      // de reprise, que le moteur traite en repartant du curseur 0.
      if (failure.statusCode == 410) throw const CursorResetRequired();
      rethrow;
    }
  }
}
