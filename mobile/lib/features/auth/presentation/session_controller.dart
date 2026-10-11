import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/network.dart';
import '../../../core/errors/failures.dart';
import '../../../core/providers/core_providers.dart';
import '../data/session_repository.dart';
import '../domain/session.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    ref.watch(databaseProvider).settingsDao,
    tokens: ref.watch(tokenStoreProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

/// Session courante. Son chargement (ouverture de la base, lecture des
/// préférences) est ce que l'écran de démarrage attend.
final sessionProvider = AsyncNotifierProvider<SessionController, Session>(
  SessionController.new,
);

/// Propriétaire des données affichées : `null` pour le profil local.
final currentOwnerProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider).value?.ownerId,
);

class SessionController extends AsyncNotifier<Session> {
  SessionRepository get _repo => ref.read(sessionRepositoryProvider);

  @override
  Future<Session> build() => ref.watch(sessionRepositoryProvider).load();

  Future<void> completeOnboarding() async {
    await _repo.markOnboardingSeen();
    state = AsyncData(_current.copyWith(onboardingSeen: true));
  }

  Future<void> startLocalMode() async {
    await _repo.startLocalMode();
    state = AsyncData(_current.copyWith(mode: SessionMode.local));
  }

  /// Crée un compte et ouvre la session (§3.C).
  ///
  /// Les erreurs remontent à l'écran, qui affiche le message et les erreurs
  /// par champ de l'API : l'état [sessionProvider] reste celui d'avant l'appel.
  Future<void> register({
    required String email,
    required String password,
    required String firstName,
  }) async {
    final session = await ref
        .read(authApiProvider)
        .register(email: email, password: password, firstName: firstName);
    await _repo.signIn(session);
    state = AsyncData(await _repo.load());
  }

  Future<void> signIn({required String email, required String password}) async {
    final session = await ref
        .read(authApiProvider)
        .login(email: email, password: password);
    await _repo.signIn(session);
    state = AsyncData(await _repo.load());
  }

  /// Déconnexion (D34 = « Se déconnecter »).
  ///
  /// Le serveur est prévenu pour révoquer le jeton de rafraîchissement, mais
  /// **une panne réseau ne bloque jamais la déconnexion locale** : rester
  /// connecté parce que le réseau est coupé serait le pire des deux mondes.
  /// L'outbox n'est jamais touchée (§6).
  Future<void> signOut() async {
    final tokens = await _repo.tokens.read();
    if (tokens != null) {
      try {
        await ref.read(authApiProvider).logout(tokens.refresh);
      } on Failure {
        // Sans importance : les jetons sont effacés localement juste après.
      }
    }
    await _repo.signOut();
    state = AsyncData(await _repo.load());
  }

  /// Relit l'identité depuis le serveur et met à jour l'affichage local.
  Future<void> refreshAccount() async {
    final account = await ref.read(authApiProvider).me();
    await _repo.updateAccount(account);
    state = AsyncData(await _repo.load());
  }

  /// Relance le chargement (bouton « Réessayer » de l'écran de démarrage).
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.load);
  }

  Session get _current => state.value ?? Session.initial;
}
