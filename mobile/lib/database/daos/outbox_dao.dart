import 'package:drift/drift.dart';

import '../../core/model/enums.dart';
import '../app_database.dart';
import '../tables/outbox_table.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.attachedDatabase);

  /// Nombre d'opérations restant à envoyer pour un compte.
  Stream<int> watchPendingCount(String userId) {
    final count = outbox.seq.count();
    return (selectOnly(outbox)
          ..addColumns([count])
          ..where(
            outbox.userId.equals(userId) &
                outbox.status.equalsValue(OutboxStatus.pending),
          ))
        .map((row) => row.read(count)!)
        .watchSingle();
  }

  /// Dernière entrée en attente pour un enregistrement (compactage).
  Future<OutboxEntry?> lastPendingFor(String entityId) =>
      (select(outbox)
            ..where(
              (o) =>
                  o.entityId.equals(entityId) &
                  o.status.equalsValue(OutboxStatus.pending),
            )
            ..orderBy([(o) => OrderingTerm.desc(o.seq)])
            ..limit(1))
          .getSingleOrNull();

  Future<bool> hasPendingFor(String entityId) async =>
      (await lastPendingFor(entityId)) != null;

  /// Prochaines entrées envoyables, dans l'ordre d'écriture.
  Future<List<OutboxEntry>> nextBatch(
    String userId,
    DateTime now, {
    int limit = 100,
  }) =>
      (select(outbox)
            ..where(
              (o) =>
                  o.userId.equals(userId) &
                  o.status.equalsValue(OutboxStatus.pending) &
                  (o.nextAttemptAt.isNull() |
                      o.nextAttemptAt.isSmallerOrEqualValue(now)),
            )
            ..orderBy([(o) => OrderingTerm.asc(o.seq)])
            ..limit(limit))
          .get();

  Stream<List<OutboxEntry>> watchFailed(String userId) =>
      (select(outbox)
            ..where(
              (o) =>
                  o.userId.equals(userId) &
                  o.status.equalsValue(OutboxStatus.failed),
            )
            ..orderBy([(o) => OrderingTerm.asc(o.seq)]))
          .watch();

  Stream<int> watchFailedCount(String userId) {
    final count = outbox.seq.count();
    return (selectOnly(outbox)
          ..addColumns([count])
          ..where(
            outbox.userId.equals(userId) &
                outbox.status.equalsValue(OutboxStatus.failed),
          ))
        .map((row) => row.read(count)!)
        .watchSingle();
  }

  /// Nombre d'entrées en attente pour un enregistrement (rebasage : savoir si
  /// l'enregistrement reste `pending` après le retrait de l'opération envoyée).
  Future<int> pendingCountFor(String entityId) async {
    final count = outbox.seq.count();
    final row =
        await (selectOnly(outbox)
              ..addColumns([count])
              ..where(
                outbox.entityId.equals(entityId) &
                    outbox.status.equalsValue(OutboxStatus.pending),
              ))
            .getSingle();
    return row.read(count)!;
  }

  // -------------------------------------------------------------------------
  // Cycle de synchronisation (§3)
  // -------------------------------------------------------------------------

  /// `attempts += 1`, **avant** l'envoi.
  ///
  /// Une entrée déjà tentée n'est plus compactée par `planOutboxWrite` : elle a
  /// peut-être été appliquée côté serveur, et l'écraser ferait diverger l'état
  /// local de l'état serveur.
  Future<void> markAttempt(int seq, int attempts) =>
      (update(outbox)..where((o) => o.seq.equals(seq))).write(
        OutboxCompanion(attempts: Value(attempts)),
      );

  /// Repousse une entrée après une panne temporaire (recul exponentiel).
  Future<void> scheduleRetry(int seq, DateTime at, String errorCode) =>
      (update(outbox)..where((o) => o.seq.equals(seq))).write(
        OutboxCompanion(nextAttemptAt: Value(at), lastError: Value(errorCode)),
      );

  /// Rejet définitif : l'entrée est conservée pour l'affichage, elle ne repart
  /// plus automatiquement.
  Future<void> markFailed(int seq, String errorCode) =>
      (update(outbox)..where((o) => o.seq.equals(seq))).write(
        OutboxCompanion(
          status: const Value(OutboxStatus.failed),
          nextAttemptAt: const Value(null),
          lastError: Value(errorCode),
        ),
      );

  /// Même chose, en repartant de la clé d'idempotence renvoyée par le serveur.
  Future<void> markFailedByOpId(String opId, String errorCode) =>
      (update(outbox)..where((o) => o.opId.equals(opId))).write(
        OutboxCompanion(
          status: const Value(OutboxStatus.failed),
          nextAttemptAt: const Value(null),
          lastError: Value(errorCode),
        ),
      );

  /// Retire les entrées envoyées, par clé d'idempotence.
  Future<void> removeByOpIds(Iterable<String> opIds) async {
    final ids = opIds.toList(growable: false);
    if (ids.isEmpty) return;
    await (delete(outbox)..where((o) => o.opId.isIn(ids))).go();
  }

  /// Rebase les entrées non encore envoyées d'un enregistrement sur la version
  /// renvoyée par le serveur.
  Future<void> rebasePendingFor(String entityId, int version) =>
      (update(outbox)..where(
            (o) =>
                o.entityId.equals(entityId) &
                o.status.equalsValue(OutboxStatus.pending),
          ))
          .write(OutboxCompanion(baseVersion: Value(version)));

  /// Supprime l'outbox d'un enregistrement — utilisé quand le budget local
  /// cède la place à celui du serveur (D33).
  Future<void> deleteAllFor(String entityId) =>
      (delete(outbox)..where((o) => o.entityId.equals(entityId))).go();

  /// Rejoue une entrée en échec depuis l'écran des opérations en échec.
  Future<void> retry(int seq, DateTime now) =>
      (update(outbox)..where((o) => o.seq.equals(seq))).write(
        OutboxCompanion(
          status: const Value(OutboxStatus.pending),
          nextAttemptAt: Value(now),
          lastError: const Value(null),
        ),
      );
}
