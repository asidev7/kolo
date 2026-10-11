import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/errors/failures.dart';
import '../domain/tokens.dart';

/// Coffre des jetons d'authentification.
///
/// Interface volontairement étroite : les couches au-dessus n'ont pas à
/// savoir *où* les jetons sont rangés, et les tests utilisent une
/// implémentation en mémoire.
abstract interface class TokenStore {
  Future<Tokens?> read();

  Future<void> write(Tokens tokens);

  /// Efface les jetons. **Ne touche jamais à l'outbox** : les opérations en
  /// attente repartent à la prochaine connexion (§6).
  Future<void> clear();
}

/// Coffre du système : Keychain sur iOS, Keystore sur Android.
///
/// Aucun jeton ne transite par `app_settings`, qui n'est pas chiffré
/// (ARCHITECTURE §5).
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'auth.access_token';
  static const _refreshKey = 'auth.refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<Tokens?> read() async {
    try {
      final access = await _storage.read(key: _accessKey);
      final refresh = await _storage.read(key: _refreshKey);
      if (access == null || refresh == null || access.isEmpty) return null;
      return Tokens(access: access, refresh: refresh);
    } on Object {
      // Coffre illisible (appareil verrouillé, entrée corrompue) : on repart
      // de zéro plutôt que d'empêcher l'application de démarrer.
      return null;
    }
  }

  @override
  Future<void> write(Tokens tokens) async {
    try {
      await _storage.write(key: _accessKey, value: tokens.access);
      await _storage.write(key: _refreshKey, value: tokens.refresh);
    } on Object {
      throw const StorageFailure(
        'Impossible de conserver la connexion sur ce téléphone.',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } on Object {
      // Effacer des jetons déjà absents n'est pas une erreur pour l'appelant.
    }
  }
}
