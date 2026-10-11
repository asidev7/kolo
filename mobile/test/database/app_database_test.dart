import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/database/app_database.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = newTestDatabase());
  tearDown(() => db.close());

  test('les catégories par défaut sont créées avec leurs UUID fixes', () async {
    final rows = await db.select(db.categories).get();
    expect(rows, hasLength(DefaultCategories.all.length));
    expect(
      rows.map((r) => r.id).toSet(),
      DefaultCategories.all.map((c) => c.id).toSet(),
    );
    expect(rows.every((r) => r.isDefault && r.userId == null), isTrue);
  });

  test('le seeding est idempotent', () async {
    await db.seedDefaultCategories();
    await db.seedDefaultCategories();
    final count = await db.select(db.categories).get();
    expect(count, hasLength(DefaultCategories.all.length));
  });

  test('les clés étrangères sont actives', () async {
    final now = DateTime.utc(2026, 10, 9);
    await expectLater(
      db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-1',
              type: TransactionType.expense,
              amount: 1500,
              categoryId: 'inexistante',
              occurredOn: '2026-10-09',
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.localOnly,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('un montant nul ou négatif est refusé par la base', () async {
    final now = DateTime.utc(2026, 10, 9);
    for (final amount in [0, -5]) {
      await expectLater(
        db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: 'tx-$amount',
                type: TransactionType.expense,
                amount: amount,
                categoryId: DefaultCategories.all.first.id,
                occurredOn: '2026-10-09',
                createdAt: now,
                updatedAt: now,
                syncStatus: SyncStatus.localOnly,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    }
  });

  test('deux catégories actives homonymes sont refusées', () async {
    final now = DateTime.utc(2026, 10, 9);
    await expectLater(
      db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'custom-1',
              name: 'alimentation',
              type: TransactionType.expense,
              icon: 'food',
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.localOnly,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });
}
