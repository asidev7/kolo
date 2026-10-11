import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/local_date.dart';
import 'package:kolo/core/utils/text_normalize.dart';
import 'package:kolo/database/app_database.dart';

import '../helpers/test_database.dart';

final foodId = DefaultCategories.all[0].id;
final transportId = DefaultCategories.all[1].id;
final salaryId = DefaultCategories.all
    .firstWhere((c) => c.type == TransactionType.income)
    .id;

void main() {
  late AppDatabase db;
  var counter = 0;

  setUp(() => db = newTestDatabase());
  tearDown(() => db.close());

  Future<void> add({
    required int amount,
    required String on,
    TransactionType type = TransactionType.expense,
    String? category,
    String? userId,
    String? note,
    bool deleted = false,
    DateTime? createdAt,
    String? id,
  }) async {
    counter++;
    final created = createdAt ?? DateTime.utc(2026, 10, 9, 0, 0, counter);
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id ?? 'tx-${counter.toString().padLeft(4, '0')}',
            userId: Value(userId),
            type: type,
            amount: amount,
            categoryId:
                category ??
                (type == TransactionType.income ? salaryId : foodId),
            note: Value(note),
            noteSearch: Value(note == null ? null : normalizeForSearch(note)),
            occurredOn: on,
            createdAt: created,
            updatedAt: created,
            deletedAt: Value(deleted ? created : null),
            syncStatus: SyncStatus.localOnly,
          ),
        );
  }

  group('totaux', () {
    test('solde : supprimées exclues, propriétaire respecté', () async {
      await add(amount: 50000, on: '2026-10-01', type: TransactionType.income);
      await add(amount: 1500, on: '2026-10-02');
      await add(amount: 9999, on: '2026-10-02', deleted: true);
      await add(amount: 777, on: '2026-10-02', userId: 'autre');
      final totals = await db.transactionsDao.watchTotals(null).first;
      expect(totals, const TypeTotals(income: 50000, expense: 1500));
    });

    test(
      'limites de mois : 30/09 et 01/11 exclus du mois d\'octobre',
      () async {
        await add(amount: 1, on: '2026-09-30');
        await add(amount: 10, on: '2026-10-01');
        await add(amount: 100, on: '2026-10-31');
        await add(amount: 1000, on: '2026-11-01');
        const october = YearMonth(2026, 10);
        final totals = await db.transactionsDao
            .watchTotals(null, from: october.firstDay, to: october.lastDay)
            .first;
        expect(totals.expense, 110);
      },
    );

    test('totaux mensuels sur 6 mois', () async {
      await add(amount: 100, on: '2026-05-15');
      await add(amount: 200, on: '2026-10-01', type: TransactionType.income);
      await add(amount: 300, on: '2026-10-20');
      final byMonth = await db.transactionsDao
          .watchMonthlyTotals(
            null,
            const YearMonth(2026, 5),
            const YearMonth(2026, 10),
          )
          .first;
      expect(byMonth['2026-05'], const TypeTotals(income: 0, expense: 100));
      expect(byMonth['2026-10'], const TypeTotals(income: 200, expense: 300));
    });

    test('répartition par catégorie triée par montant', () async {
      await add(amount: 100, on: '2026-10-01', category: foodId);
      await add(amount: 500, on: '2026-10-02', category: transportId);
      await add(amount: 50, on: '2026-10-03', category: foodId);
      final rows = await db.transactionsDao
          .watchTotalsByCategory(
            null,
            TransactionType.expense,
            const LocalDate(2026, 10, 1),
            const LocalDate(2026, 10, 31),
          )
          .first;
      expect(rows.map((r) => (r.categoryId, r.total)), [
        (transportId, 500),
        (foodId, 150),
      ]);
    });

    test('dépenses par jour', () async {
      await add(amount: 100, on: '2026-10-01');
      await add(amount: 50, on: '2026-10-01');
      await add(amount: 999, on: '2026-10-01', type: TransactionType.income);
      final byDay = await db.transactionsDao
          .watchDailyExpenses(
            null,
            const LocalDate(2026, 10, 1),
            const LocalDate(2026, 10, 31),
          )
          .first;
      expect(byDay, {'2026-10-01': 150});
    });
  });

  group('historique', () {
    test('pagination par curseur : ordre stable, ni trou ni doublon', () async {
      // 120 opérations dont plusieurs le même jour et à la même seconde.
      for (var i = 0; i < 120; i++) {
        await add(
          amount: i + 1,
          on: '2026-10-${(i % 5 + 1).toString().padLeft(2, '0')}',
          createdAt: DateTime.utc(2026, 10, 9, 0, 0, i % 3),
        );
      }
      const query = TransactionQuery(userId: null);
      final seen = <String>[];
      HistoryCursor? cursor;
      while (true) {
        final page = await db.transactionsDao.pageAfter(
          query,
          after: cursor,
          limit: 50,
        );
        if (page.isEmpty) break;
        seen.addAll(page.map((r) => r.id));
        cursor = HistoryCursor.of(page.last);
      }
      expect(seen, hasLength(120));
      expect(seen.toSet(), hasLength(120));

      final all = await db.transactionsDao.pageAfter(query, limit: 1000);
      expect(seen, all.map((r) => r.id).toList());
      for (var i = 1; i < all.length; i++) {
        expect(
          all[i - 1].occurredOn.compareTo(all[i].occurredOn),
          greaterThanOrEqualTo(0),
        );
      }
    });

    test('watchUntil recharge exactement les pages déjà affichées', () async {
      for (var i = 0; i < 10; i++) {
        await add(amount: 1, on: '2026-10-0${i % 9 + 1}');
      }
      const query = TransactionQuery(userId: null);
      final firstPage = await db.transactionsDao.pageAfter(query, limit: 4);
      final reloaded = await db.transactionsDao
          .watchUntil(query, HistoryCursor.of(firstPage.last))
          .first;
      expect(reloaded.map((r) => r.id), firstPage.map((r) => r.id));
    });

    test(
      'recherche insensible à la casse/accents, jokers neutralisés',
      () async {
        await add(amount: 1, on: '2026-10-01', note: 'Zém marché');
        await add(amount: 2, on: '2026-10-01', note: 'Crédit 100%');
        await add(amount: 3, on: '2026-10-01', note: 'Autre');

        Future<List<int>> search(String q) async =>
            (await db.transactionsDao.pageAfter(
              TransactionQuery(userId: null, search: q),
            )).map((r) => r.amount).toList();

        expect(await search('ZÉM'), [1]);
        expect(await search('zem MARCHE'), [1]);
        expect(await search('100%'), [2]);
        expect(await search('%'), [2]);
      },
    );

    test('filtres combinés : type, période, catégorie', () async {
      await add(amount: 1, on: '2026-10-01', category: foodId);
      await add(amount: 2, on: '2026-10-15', category: transportId);
      await add(amount: 3, on: '2026-10-20', type: TransactionType.income);
      await add(amount: 4, on: '2026-09-20', category: transportId);

      final rows = await db.transactionsDao.pageAfter(
        TransactionQuery(
          userId: null,
          type: TransactionType.expense,
          from: const LocalDate(2026, 10, 1),
          to: const LocalDate(2026, 10, 31),
          categoryIds: {transportId},
        ),
      );
      expect(rows.map((r) => r.amount), [2]);
    });

    test('les supprimées n\'apparaissent jamais', () async {
      await add(amount: 1, on: '2026-10-01', deleted: true);
      final rows = await db.transactionsDao.pageAfter(
        const TransactionQuery(userId: null),
      );
      expect(rows, isEmpty);
    });
  });

  test('dernière catégorie utilisée', () async {
    await add(amount: 1, on: '2026-10-01', category: foodId);
    await add(amount: 1, on: '2026-09-01', category: transportId);
    expect(
      await db.transactionsDao.lastUsedCategoryId(
        null,
        TransactionType.expense,
      ),
      transportId, // créée en dernier, même si sa date métier est plus ancienne
    );
  });
}
