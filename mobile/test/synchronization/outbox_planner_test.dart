import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/synchronization/outbox/outbox_planner.dart';

OutboxRequest request(
  OutboxOpType op, {
  int baseVersion = 0,
  Set<String> changed = const {'amount'},
}) => OutboxRequest(
  entity: SyncEntity.transaction,
  entityId: 'tx',
  opType: op,
  payload: const {'amount': 1},
  changedFields: changed,
  baseVersion: baseVersion,
  userId: 'u1',
);

PendingOutboxEntry pending(
  OutboxOpType op, {
  int baseVersion = 0,
  int attempts = 0,
  Set<String> changed = const {'note'},
}) => PendingOutboxEntry(
  seq: 7,
  opType: op,
  baseVersion: baseVersion,
  attempts: attempts,
  changedFields: changed,
);

void main() {
  test('rien en attente → ajout', () {
    expect(
      planOutboxWrite(null, request(OutboxOpType.upsert)),
      isA<AppendEntry>(),
    );
  });

  test('entrée déjà tentée → jamais modifiée, nouvel ajout', () {
    final plan = planOutboxWrite(
      pending(OutboxOpType.upsert, attempts: 1),
      request(OutboxOpType.upsert, baseVersion: 0),
    );
    expect(plan, isA<AppendEntry>());
  });

  test('deux modifications non envoyées → fusion avec la base_version la plus ancienne', () {
    final plan = planOutboxWrite(
      pending(OutboxOpType.upsert, baseVersion: 3),
      request(OutboxOpType.upsert, baseVersion: 3, changed: {'amount'}),
    );
    expect(plan, isA<ReplaceEntry>());
    final replace = plan as ReplaceEntry;
    expect(replace.seq, 7);
    expect(replace.request.baseVersion, 3);
    expect(replace.request.changedFields, {'note', 'amount'});
  });

  test('création non envoyée puis suppression → annulation complète', () {
    final plan = planOutboxWrite(
      pending(OutboxOpType.upsert, baseVersion: 0),
      request(OutboxOpType.delete),
    );
    expect(plan, isA<CancelEntry>());
  });

  test('modification non envoyée puis suppression d\'un enregistrement connu du serveur → suppression', () {
    final plan = planOutboxWrite(
      pending(OutboxOpType.upsert, baseVersion: 2),
      request(OutboxOpType.delete, baseVersion: 2),
    );
    expect(plan, isA<ReplaceEntry>());
    expect((plan as ReplaceEntry).request.opType, OutboxOpType.delete);
    expect(plan.request.baseVersion, 2);
  });

  test('diffFields', () {
    expect(diffFields({'a': 1, 'b': 2}, {'a': 1, 'b': 3, 'c': null}), {'b'});
    expect(diffFields({'a': 1}, {'a': 1}), isEmpty);
  });
}
