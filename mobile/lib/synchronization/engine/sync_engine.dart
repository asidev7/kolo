import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../core/errors/failures.dart';
import '../../core/utils/time_source.dart';
import '../../database/app_database.dart';
import '../api/sync_api.dart';
import '../apply/remote_apply.dart';
import '../wire/sync_dto.dart';
import 'backoff.dart';
import 'push_planner.dart';
import 'sync_lease.dart';

/// Identité nécessaire au moteur — sans dépendre des écrans (`features/auth`).
///
/// Le sens des dépendances va des écrans vers le moteur : c'est la racine de
/// composition (`app/sync.dart`) qui branche la session sur ce petit objet.
@immutable
class SyncAccount {
  const SyncAccount({required this.userId, required this.deviceId});

  final String userId;

  /// Identifiant de l'installation, journalisé par le serveur (support).
  final String deviceId;
}

typedef SyncAccountLookup = Future<SyncAccount?> Function();

/// Issue d'un cycle complet.
enum SyncResult {
  /// Push et pull terminés sans erreur.
  synced,

  /// Mode local : il n'y a rien à synchroniser.
  localMode,

  /// Un autre cycle est déjà en cours (autre isolate).
  skipped,

  /// Panne temporaire : réessayer plus tard.
  retryLater,

  /// La session n'est plus valable : reconnexion nécessaire.
  sessionExpired,

  /// Échec inattendu (réponse illisible, contrainte locale…).
  failed,
}

@immutable
class SyncReport {
  const SyncReport(
    this.result, {
    this.message,
    this.pushed = 0,
    this.applied = 0,
  });

  final SyncResult result;
  final String? message;
  final int pushed;
  final int applied;

  bool get isSuccess => result == SyncResult.synced;
}

/// Un cycle de synchronisation : push puis pull (§3).
///
/// Un seul cycle à la fois dans le processus (voir [syncNow]) et un seul par
/// appareil (voir [SyncLease]).
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required this.api,
    required this.applier,
    required this.accountLookup,
    required TimeSource time,
    SyncLease? lease,
    this.jitter = defaultJitter,
    this.pullLimit = defaultPullLimit,
  }) : _db = db,
       _time = time,
       _lease = lease ?? SyncLease(db.settingsDao, time);

  /// Taille de page du pull : la valeur par défaut du serveur.
  static const int defaultPullLimit = 500;

  /// Garde-fous : un cycle reste borné même si le serveur répond mal.
  static const int maxPushRounds = 20;
  static const int maxPullPages = 100;

  final AppDatabase _db;

  /// Transport vers le serveur. Public : la tâche de fond et les tests
  /// construisent leur propre pile et n'ont rien à cacher.
  final SyncApi api;

  /// Écrit ce qui vient du serveur — le seul chemin d'écriture distant.
  final RemoteApplier applier;

  /// Identité du compte courant, ou `null` en mode local.
  final SyncAccountLookup accountLookup;
  final TimeSource _time;
  final SyncLease _lease;

  /// Aléa du recul exponentiel, injectable pour des tests déterministes.
  final JitterSource jitter;
  final int pullLimit;

  Future<SyncReport>? _running;

  /// Lance un cycle, ou s'accroche à celui déjà en cours.
  ///
  /// Les déclencheurs sont nombreux (écriture locale, réveil, retour du
  /// réseau, tâche de fond) et se chevauchent : un seul cycle doit toucher le
  /// curseur à la fois.
  Future<SyncReport> syncNow() {
    final running = _running;
    if (running != null) return running;
    final future = _run();
    _running = future;
    return future;
  }

  Future<SyncReport> _run() async {
    String? userId;
    try {
      final identity = await accountLookup();
      if (identity == null) return const SyncReport(SyncResult.localMode);
      userId = identity.userId;

      if (!await _lease.acquire(identity.userId)) {
        return const SyncReport(SyncResult.skipped);
      }
      try {
        final pushed = await _push(identity);
        final applied = await _pull(identity);
        return SyncReport(SyncResult.synced, pushed: pushed, applied: applied);
      } finally {
        await _lease.release(identity.userId);
      }
    } on SessionExpiredFailure catch (failure) {
      // L'outbox n'est jamais touchée : tout repartira après reconnexion (§6).
      await _recordFailure(userId, 'session_expired');
      return SyncReport(SyncResult.sessionExpired, message: failure.message);
    } on RetryableFailure catch (failure) {
      await _recordFailure(userId, 'network');
      return SyncReport(SyncResult.retryLater, message: failure.message);
    } on ApiFailure catch (failure) {
      await _recordFailure(userId, failure.code);
      return SyncReport(SyncResult.failed, message: failure.message);
    } on Failure catch (failure) {
      await _recordFailure(userId, 'unexpected');
      return SyncReport(SyncResult.failed, message: failure.message);
    } catch (error) {
      // Un plantage du moteur ne doit jamais remonter jusqu'à l'écran : la
      // saisie de l'utilisateur, elle, est déjà en base.
      await _recordFailure(userId, 'unexpected');
      return SyncReport(SyncResult.failed, message: userMessageFor(error));
    } finally {
      _running = null;
    }
  }

  // -------------------------------------------------------------------------
  // Push
  // -------------------------------------------------------------------------

  Future<int> _push(SyncAccount account) async {
    var pushed = 0;
    for (var round = 0; round < maxPushRounds; round++) {
      final due = await _db.outboxDao.nextBatch(
        account.userId,
        _time.nowUtc(),
        limit: maxOperationsPerPush * 3,
      );
      if (due.isEmpty) return pushed;

      final batch = selectPushBatch(due);
      if (batch.isEmpty) return pushed;

      // `attempts += 1` **avant** l'envoi : si l'application est tuée pendant
      // la requête, l'entrée ne sera plus compactée et le serveur arbitrera
      // par `op_id`.
      for (final entry in batch) {
        await _db.outboxDao.markAttempt(entry.seq, entry.attempts + 1);
      }

      final PushResponse response;
      try {
        response = await api.push(
          deviceId: account.deviceId,
          operations: [
            for (final entry in batch) PushOperation.fromEntry(entry),
          ],
        );
      } on Failure catch (failure) {
        // Panne temporaire ou session expirée : le serveur n'a rien appliqué.
        // Sauf pour une session expirée, on repousse le lot selon le recul
        // exponentiel pour ne pas marteler le serveur.
        if (failure is! SessionExpiredFailure) {
          await _scheduleRetry(batch);
        }
        rethrow;
      }

      final report = await applier.applyPushResults(
        userId: account.userId,
        outcomes: response.results,
      );
      await _rebase(response.results);
      if (report.requiresFullPull) {
        // D33 : un pull complet installera l'enregistrement du serveur.
        await _resetCursor(account.userId);
      }

      pushed += batch.length;
      if (response.results.isEmpty) return pushed;
    }
    return pushed;
  }

  /// Rebase les opérations encore en attente d'un enregistrement qui vient
  /// d'être appliqué : sans cela elles repartiraient sur l'ancienne version et
  /// le serveur les refuserait en conflit alors que le client est à jour.
  Future<void> _rebase(List<PushOutcome> outcomes) async {
    for (final target in rebaseTargets(outcomes)) {
      await _db.outboxDao.rebasePendingFor(target.entityId, target.version);
    }
  }

  Future<void> _scheduleRetry(List<OutboxEntry> batch) async {
    final now = _time.nowUtc();
    for (final entry in batch) {
      await _db.outboxDao.scheduleRetry(
        entry.seq,
        nextAttemptAt(now, entry.attempts + 1, random: jitter()),
        'network',
      );
    }
  }

  Future<void> _resetCursor(String userId) => _db.syncStateDao.save(
    SyncStateCompanion(userId: Value(userId), cursor: const Value('0')),
  );

  // -------------------------------------------------------------------------
  // Pull
  // -------------------------------------------------------------------------

  Future<int> _pull(SyncAccount account) async {
    var cursor = (await _db.syncStateDao.find(account.userId))?.cursor ?? '0';
    // Un curseur à 0 est un pull complet : il autorise la purge des
    // enregistrements confirmés que le serveur ne connaît plus.
    var full = cursor == '0';
    var applied = 0;
    final seen = <String>{};

    for (var page = 0; page < maxPullPages; page++) {
      final PullPage result;
      try {
        result = await api.pull(cursor: cursor, limit: pullLimit);
      } on CursorResetRequired {
        cursor = '0';
        full = true;
        seen.clear();
        continue;
      }

      if (full) {
        for (final record in result.changes) {
          seen.add(record.entityId);
        }
      }

      await applier.applyPull(
        userId: account.userId,
        records: result.changes,
        nextCursor: result.nextCursor,
        serverTime: result.serverTime,
      );
      applied += result.changes.length;
      cursor = result.nextCursor;

      if (!result.hasMore) {
        if (full) {
          await applier.purgeSyncedNotSeen(
            userId: account.userId,
            seenIds: seen,
          );
        }
        return applied;
      }
    }
    return applied;
  }

  Future<void> _recordFailure(String? userId, String code) async {
    if (userId == null) return;
    await _db.syncStateDao.save(
      SyncStateCompanion(
        userId: Value(userId),
        lastAttemptAt: Value(_time.nowUtc()),
        lastError: Value(code),
      ),
    );
  }
}
