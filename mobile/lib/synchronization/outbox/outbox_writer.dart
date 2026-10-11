import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/utils/time_source.dart';
import '../../database/app_database.dart';
import 'outbox_planner.dart';

/// Point d'entrée unique des écritures métier (§4.2, étape 3).
///
/// [transaction] ouvre une transaction SQLite et fournit un [OutboxRecorder]
/// qui n'existe que pendant celle-ci : il est impossible d'écrire dans
/// l'outbox hors de la transaction de l'enregistrement métier.
class OutboxWriter {
  OutboxWriter(this._db, this._time, this._ids);

  final AppDatabase _db;
  final TimeSource _time;
  final IdGenerator _ids;

  Future<T> transaction<T>(Future<T> Function(OutboxRecorder outbox) body) =>
      _db.transaction(() => body(OutboxRecorder._(this)));

  Future<void> _record(OutboxRequest request) async {
    final last = await _db.outboxDao.lastPendingFor(request.entityId);
    final pending = last == null
        ? null
        : PendingOutboxEntry(
            seq: last.seq,
            opType: last.opType,
            baseVersion: last.baseVersion,
            attempts: last.attempts,
            changedFields: (jsonDecode(last.changedFields) as List<Object?>)
                .cast<String>()
                .toSet(),
          );

    switch (planOutboxWrite(pending, request)) {
      case AppendEntry(:final request):
        await _db.into(_db.outbox).insert(_companion(request));
      case ReplaceEntry(:final seq, :final request):
        await (_db.delete(_db.outbox)..where((o) => o.seq.equals(seq))).go();
        await _db.into(_db.outbox).insert(_companion(request));
      case CancelEntry(:final seq):
        await (_db.delete(_db.outbox)..where((o) => o.seq.equals(seq))).go();
    }
  }

  OutboxCompanion _companion(OutboxRequest r) => OutboxCompanion.insert(
    // Nouvelle clé d'idempotence à chaque contenu nouveau.
    opId: _ids(),
    entity: r.entity,
    entityId: r.entityId,
    opType: r.opType,
    payload: jsonEncode(r.payload),
    changedFields: Value(jsonEncode(r.changedFields.toList()..sort())),
    baseVersion: r.baseVersion,
    userId: r.userId,
    createdAt: _time.nowUtc(),
  );
}

/// Enregistreur d'outbox valable uniquement dans [OutboxWriter.transaction].
class OutboxRecorder {
  OutboxRecorder._(this._writer);

  final OutboxWriter _writer;

  Future<void> record(OutboxRequest request) => _writer._record(request);
}
