import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/errors/failures.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/local_date.dart';
import 'package:kolo/database/app_database.dart';
import 'package:kolo/features/transactions/data/transactions_repository.dart';
import 'package:kolo/features/transactions/domain/transaction.dart';
import 'package:kolo/synchronization/outbox/outbox_writer.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_database.dart';

final food = DefaultCategories.all.first; // Alimentation (dépense)
final salary = DefaultCategories.all.firstWhere(
  (c) => c.type == TransactionType.income,
);

TransactionDraft expense(int amount, {String? note, LocalDate? on}) =>
    TransactionDraft(
      type: TransactionType.expense,
      amount: amount,
      categoryId: food.id,
      note: note,
      occurredOn: on ?? const LocalDate(2026, 10, 9),
    );

void main() {
  late AppDatabase db;
  late FakeTime time;
  late SequentialIds ids;
  late TransactionsRepository repo;
  late int writes;

  setUp(() {
    db = newTestDatabase();
    time = FakeTime();
    ids = SequentialIds('op');
    writes = 0;
    repo = TransactionsRepository(
      db: db,
      writer: OutboxWriter(db, time.source, ids.call),
      time: time.source,
      onLocalWrite: () => writes++,
    );
  });

  tearDown(() => db.close());

  Future<List<OutboxEntry>> outbox() =>
      (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();

  group('mode local (sans compte)', () {
    test('création : statut local_only, aucune entrée outbox', () async {
      final outcome = await repo.save(
        id: 'tx1',
        ownerId: null,
        draft: expense(1500, note: 'Zém'),
      );
      expect(outcome, SaveOutcome.created);
      final row = (await db.transactionsDao.findById('tx1'))!;
      expect(row.syncStatus, SyncStatus.localOnly);
      expect(row.userId, isNull);
      expect(row.noteSearch, 'zem');
      expect(row.createdAt, time.now);
      expect(await outbox(), isEmpty);
      expect(writes, 1);
    });

    test(
      'double soumission avec le même identifiant : aucun doublon',
      () async {
        await repo.save(id: 'tx1', ownerId: null, draft: expense(1500));
        final second = await repo.save(
          id: 'tx1',
          ownerId: null,
          draft: expense(1500),
        );
        expect(second, SaveOutcome.unchanged);
        expect(await db.transactionsDao.countAlive(null), 1);
        expect(writes, 1);
      },
    );

    test('saisie invalide : rien n\'est écrit', () async {
      await expectLater(
        repo.save(id: 'tx1', ownerId: null, draft: expense(0)),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await db.transactionsDao.findById('tx1'), isNull);
    });

    test('catégorie incompatible avec le type : refusée', () async {
      final draft = TransactionDraft(
        type: TransactionType.income,
        amount: 1000,
        categoryId: food.id,
        occurredOn: const LocalDate(2026, 10, 9),
      );
      await expectLater(
        repo.save(id: 'tx1', ownerId: null, draft: draft),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('suppression = tombstone, jamais d\'effacement physique', () async {
      await repo.save(id: 'tx1', ownerId: null, draft: expense(1500));
      await repo.delete(id: 'tx1', ownerId: null);
      final row = (await db.transactionsDao.findById('tx1'))!;
      expect(row.deletedAt, isNotNull);
      expect(await db.transactionsDao.countAlive(null), 0);
      // Modifier une opération supprimée est impossible.
      await expectLater(
        repo.save(id: 'tx1', ownerId: null, draft: expense(2000)),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test(
      'les données d\'un compte ne sont pas visibles en mode local',
      () async {
        await repo.save(id: 'tx1', ownerId: 'user-a', draft: expense(1500));
        expect(await db.transactionsDao.countAlive(null), 0);
        await expectLater(
          repo.save(id: 'tx1', ownerId: null, draft: expense(9)),
          throwsA(isA<ForbiddenFailure>()),
        );
      },
    );
  });

  group('compte connecté', () {
    test('création : pending + outbox dans la même transaction', () async {
      await repo.save(
        id: 'tx1',
        ownerId: 'u1',
        draft: expense(1500, note: 'Zém'),
      );
      final row = (await db.transactionsDao.findById('tx1'))!;
      expect(row.syncStatus, SyncStatus.pending);
      final entries = await outbox();
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.opType, OutboxOpType.upsert);
      expect(e.entity, SyncEntity.transaction);
      expect(e.baseVersion, 0);
      expect(e.userId, 'u1');
      expect(jsonDecode(e.payload), {
        'type': 'expense',
        'amount': 1500,
        'currency': 'XOF',
        'category_id': food.id,
        'note': 'Zém',
        'occurred_on': '2026-10-09',
      });
    });

    test(
      'modifications successives non envoyées : compactées en une entrée',
      () async {
        await repo.save(id: 'tx1', ownerId: 'u1', draft: expense(1500));
        await repo.save(id: 'tx1', ownerId: 'u1', draft: expense(2000));
        await repo.save(
          id: 'tx1',
          ownerId: 'u1',
          draft: expense(2000, note: 'Riz'),
        );
        final entries = await outbox();
        expect(entries, hasLength(1));
        expect(
          jsonDecode(entries.single.payload),
          containsPair('amount', 2000),
        );
        expect(jsonDecode(entries.single.payload), containsPair('note', 'Riz'));
        expect(entries.single.baseVersion, 0);
      },
    );

    test('entrée déjà tentée : une nouvelle entrée est ajoutée', () async {
      await repo.save(id: 'tx1', ownerId: 'u1', draft: expense(1500));
      await db
          .update(db.outbox)
          .write(const OutboxCompanion(attempts: Value(1)));
      await repo.save(id: 'tx1', ownerId: 'u1', draft: expense(2000));
      final entries = await outbox();
      expect(entries, hasLength(2));
      expect(jsonDecode(entries.last.changedFields), ['amount']);
    });

    test(
      'créée puis supprimée avant envoi : outbox vide, tombstone conservé',
      () async {
        await repo.save(id: 'tx1', ownerId: 'u1', draft: expense(1500));
        await repo.delete(id: 'tx1', ownerId: 'u1');
        expect(await outbox(), isEmpty);
        expect(
          (await db.transactionsDao.findById('tx1'))!.deletedAt,
          isNotNull,
        );
      },
    );

    test('suppression d\'une opération synchronisée : entrée delete avec sa version', () async {
      await repo.save(id: 'tx1', ownerId: 'u1', draft: expense(1500));
      // Simule la confirmation serveur (version 4) puis le vidage de l'outbox.
      await db.delete(db.outbox).go();
      await (db.update(
        db.transactions,
      )..where((t) => t.id.equals('tx1'))).write(
        const TransactionsCompanion(
          version: Value(4),
          syncStatus: Value(SyncStatus.synced),
        ),
      );
      await repo.delete(id: 'tx1', ownerId: 'u1');
      final e = (await outbox()).single;
      expect(e.opType, OutboxOpType.delete);
      expect(e.baseVersion, 4);
    });

    test('revenu avec catégorie de revenu', () async {
      await repo.save(
        id: 'tx1',
        ownerId: 'u1',
        draft: TransactionDraft(
          type: TransactionType.income,
          amount: 50000,
          categoryId: salary.id,
          occurredOn: const LocalDate(2026, 10, 1),
        ),
      );
      final totals = await db.transactionsDao.watchTotals('u1').first;
      expect(totals.income, 50000);
    });
  });
}
