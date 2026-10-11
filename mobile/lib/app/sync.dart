import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` n'est pas réexporté par `flutter_riverpod.dart` ; en Riverpod 3
// c'est `misc.dart` qui porte les types de bas niveau.
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/network/connectivity.dart';
import '../core/providers/core_providers.dart';
import '../core/utils/time_source.dart';
import '../database/app_database.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/session_repository.dart';
import '../features/auth/data/token_refresher.dart';
import '../features/auth/data/token_store.dart';
import '../features/auth/presentation/session_controller.dart';
import '../synchronization/api/sync_api.dart';
import '../synchronization/apply/remote_apply.dart';
import '../synchronization/engine/backoff.dart';
import '../synchronization/engine/sync_badge_state.dart';
import '../synchronization/engine/sync_coordinator.dart';
import '../synchronization/engine/sync_engine.dart';
import '../synchronization/engine/sync_state.dart';
import '../synchronization/sync_providers.dart';
import 'app_config.dart';
import 'network.dart';

/// Câblage du moteur de synchronisation — racine de composition.
///
/// Le moteur ne connaît ni Riverpod ni les écrans : il reçoit une identité de
/// compte et une API. C'est ici qu'on les lui fournit, comme `app/network.dart`
/// le fait pour la pile HTTP.

/// Moteur et session, assemblés une fois pour toutes.
class SyncStack {
  const SyncStack({required this.engine, required this.session});

  final SyncEngine engine;
  final SessionRepository session;
}

/// Construit la pile complète.
///
/// Appelée par le conteneur Riverpod **et** par la tâche de fond, qui tourne
/// dans un isolate séparé sans conteneur : d'où des dépendances explicites
/// plutôt qu'un `Ref`.
SyncStack buildSyncStack({
  required AppDatabase db,
  required SessionRepository session,
  required SyncApi api,
  TimeSource time = const TimeSource(),
  JitterSource jitter = defaultJitter,
}) => SyncStack(
  session: session,
  engine: SyncEngine(
    db: db,
    api: api,
    applier: RemoteApplier(db, time),
    accountLookup: () => syncAccountFor(session),
    time: time,
    jitter: jitter,
  ),
);

/// Traduit la session locale en identité de synchronisation.
///
/// `null` en mode local : il n'y a alors rien à envoyer, et surtout aucune
/// requête à faire.
Future<SyncAccount?> syncAccountFor(SessionRepository session) async {
  final current = await session.load();
  if (!current.isAccount) return null;
  return SyncAccount(
    userId: current.userId!,
    deviceId: await session.deviceId(),
  );
}

final syncStackProvider = Provider<SyncStack>((ref) {
  final db = ref.watch(databaseProvider);
  return buildSyncStack(
    db: db,
    session: ref.watch(sessionRepositoryProvider),
    api: HttpSyncApi(ref.watch(apiClientProvider)),
    time: ref.watch(timeSourceProvider),
  );
});

/// Déclencheurs : écriture locale, retour au premier plan, réseau retrouvé.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    engine: ref.watch(syncStackProvider).engine,
    onStart: () => ref.read(syncRunStateProvider.notifier).started(),
    onFinish: (report) =>
        ref.read(syncRunStateProvider.notifier).finished(report),
  );
  coordinator.start();

  ref.listen(isOfflineProvider, (previous, next) {
    final wasOffline = previous?.value ?? false;
    final isOffline = next.value ?? false;
    if (wasOffline && !isOffline) coordinator.onConnectivityRestored();
  });

  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Branchement de l'écriture locale sur le moteur, à poser dans les
/// `overrides` du `ProviderScope` de démarrage.
///
/// `synchronization/sync_providers.dart` garde un no-op par défaut : les
/// dépôts métier n'ont ainsi aucune dépendance sur le moteur, qui n'existe pas
/// dans tous les contextes (tests, mode local).
Override localWriteSyncOverride() => localWriteSignalProvider.overrideWith(
  (ref) => ref.watch(syncCoordinatorProvider).onLocalWrite,
);

/// Où en est le moteur, pour l'affichage.
final syncRunStateProvider =
    NotifierProvider<SyncRunStateNotifier, SyncRunState>(
      SyncRunStateNotifier.new,
    );

class SyncRunStateNotifier extends Notifier<SyncRunState> {
  @override
  SyncRunState build() => const SyncRunState();

  void started() {
    if (state.isRunning) return;
    // Le message de la dernière erreur reste affiché pendant la nouvelle
    // tentative : le faire disparaître puis revenir ferait clignoter le badge.
    state = SyncRunState(phase: SyncPhase.running, message: state.message);
  }

  void finished(SyncReport report) {
    final message = switch (report.result) {
      // Seule une réussite efface l'erreur précédente : un cycle « ignoré »
      // (un autre est déjà en cours) ne prouve pas que tout va bien.
      SyncResult.synced => null,
      SyncResult.localMode || SyncResult.skipped => state.message,
      _ => report.message,
    };
    state = SyncRunState(message: message);
  }
}

/// Opérations en attente d'envoi pour le compte courant.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final owner = ref.watch(currentOwnerProvider);
  if (owner == null) return Stream.value(0);
  return ref.watch(databaseProvider).outboxDao.watchPendingCount(owner);
});

/// Curseur et dernière réussite, par compte.
final syncStateProvider = StreamProvider<SyncStateRow?>((ref) {
  final owner = ref.watch(currentOwnerProvider);
  if (owner == null) return Stream.value(null);
  return ref.watch(databaseProvider).syncStateDao.watch(owner);
});

final syncBadgeProvider = Provider<SyncBadgeState>((ref) {
  final session = ref.watch(sessionProvider).value;
  final run = ref.watch(syncRunStateProvider);
  return syncBadgeState(
    isAccount: session?.isAccount ?? false,
    offline: ref.watch(isOfflineProvider).value ?? false,
    running: run.isRunning,
    hasError: run.message != null,
    hasSyncedOnce: ref.watch(syncStateProvider).value?.lastSuccessAt != null,
    pendingCount: ref.watch(pendingSyncCountProvider).value ?? 0,
  );
});

/// « Synchroniser maintenant » : le geste explicite de l'utilisateur.
///
/// Le `Future` se termine à la fin du cycle, pour que le
/// tirer-pour-rafraîchir sache quand arrêter son animation.
Future<SyncReport> syncNow(WidgetRef ref) =>
    ref.read(syncCoordinatorProvider).syncNow();

/// Construit la pile de la tâche de fond (isolate séparé, sans Riverpod).
SyncStack buildBackgroundSyncStack(AppDatabase db, AppConfig config) {
  final tokens = SecureTokenStore();
  final refresher = TokenRefresher(
    HttpAuthApi(plainApiClient(config.apiBaseUrl)),
    tokens,
  );
  return buildSyncStack(
    db: db,
    session: SessionRepository(
      db.settingsDao,
      tokens: tokens,
      ids: generateUuidV4,
    ),
    api: HttpSyncApi(
      buildApiClient(baseUrl: config.apiBaseUrl, refresher: refresher),
    ),
  );
}
