import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/local_date.dart';
import 'package:kolo/database/app_database.dart';
import 'package:kolo/features/transactions/data/transactions_repository.dart';
import 'package:kolo/features/transactions/domain/transaction.dart';
import 'package:kolo/synchronization/outbox/outbox_writer.dart';

import '../helpers/fakes.dart';

/// §10.3 : persistance après redémarrage (fermer / rouvrir la base) et
/// reprise de l'outbox (§4.8).
void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('kolo_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('opérations et outbox survivent à la fermeture de la base', () async {
    final file = File('${dir.path}/kolo.sqlite');
    final time = FakeTime();

    var db = AppDatabase(NativeDatabase(file));
    final repo = TransactionsRepository(
      db: db,
      writer: OutboxWriter(db, time.source, SequentialIds().call),
      time: time.source,
    );
    await repo.save(
      id: 'tx1',
      ownerId: 'u1',
      draft: TransactionDraft(
        type: TransactionType.expense,
        amount: 1500,
        categoryId: DefaultCategories.all.first.id,
        occurredOn: const LocalDate(2026, 10, 9),
      ),
    );
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.transactionsDao.findById('tx1'))?.amount, 1500);
    expect(await db.outboxDao.watchPendingCount('u1').first, 1);
    expect(
      await db.select(db.categories).get(),
      hasLength(DefaultCategories.all.length),
    );
  });
}
