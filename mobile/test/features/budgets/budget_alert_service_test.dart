import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/local_date.dart';
import 'package:kolo/database/app_database.dart';
import 'package:kolo/features/budgets/data/budget_alert_service.dart';
import 'package:kolo/features/budgets/data/budgets_repository.dart';
import 'package:kolo/features/transactions/data/transactions_repository.dart';
import 'package:kolo/features/transactions/domain/transaction.dart';
import 'package:kolo/synchronization/outbox/outbox_writer.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late BudgetsRepository budgets;
  late TransactionsRepository transactions;
  late RecordingNotifier notifier;
  late BudgetAlertService service;
  const october = YearMonth(2026, 10);
  var n = 0;

  setUp(() {
    db = newTestDatabase();
    final time = FakeTime();
    final ids = SequentialIds();
    final writer = OutboxWriter(db, time.source, ids.call);
    budgets = BudgetsRepository(
      db: db,
      writer: writer,
      time: time.source,
      ids: ids.call,
    );
    transactions = TransactionsRepository(
      db: db,
      writer: writer,
      time: time.source,
    );
    notifier = RecordingNotifier();
    service = BudgetAlertService(db: db, budgets: budgets, notifier: notifier);
  });

  tearDown(() => db.close());

  Future<void> spend(int amount) => transactions.save(
    id: 'tx-${n++}',
    ownerId: null,
    draft: TransactionDraft(
      type: TransactionType.expense,
      amount: amount,
      categoryId: DefaultCategories.all.first.id,
      occurredOn: const LocalDate(2026, 10, 5),
    ),
  );

  Future<List<int>> check() => service.check(ownerId: null, month: october);

  test('sans budget : aucune alerte', () async {
    await spend(5000);
    expect(await check(), isEmpty);
    expect(notifier.shown, isEmpty);
  });

  test('une seule notification par seuil et par mois', () async {
    await budgets.setMonthlyLimit(
      ownerId: null,
      month: october,
      limitAmount: 10000,
    );
    await spend(7000);
    expect(await check(), isEmpty);

    await spend(1000); // 80 %
    expect(await check(), [80]);
    expect(await check(), isEmpty, reason: 'déjà notifié');

    await spend(5000); // 130 %
    expect(await check(), [100]);
    expect(notifier.shown, hasLength(2));
    expect(notifier.shown.last.title, 'Budget du mois dépassé');
  });

  test('franchir deux seuils d\'un coup : une seule notification', () async {
    await budgets.setMonthlyLimit(
      ownerId: null,
      month: october,
      limitAmount: 1000,
    );
    await spend(1500);
    expect(await check(), [80, 100]);
    expect(notifier.shown, hasLength(1));
  });

  test('alertes désactivées', () async {
    await budgets.setMonthlyLimit(
      ownerId: null,
      month: october,
      limitAmount: 1000,
    );
    await service.setAlertsEnabled(enabled: false);
    await spend(1500);
    expect(await check(), isEmpty);
  });

  test('reconduction : le budget d\'octobre s\'applique en novembre', () async {
    await budgets.setMonthlyLimit(
      ownerId: null,
      month: october,
      limitAmount: 30000,
    );
    final november = await budgets.getEffective(
      null,
      const YearMonth(2026, 11),
    );
    expect(november?.limitAmount, 30000);
    final september = await budgets.getEffective(
      null,
      const YearMonth(2026, 9),
    );
    expect(september, isNull);

    await budgets.setMonthlyLimit(
      ownerId: null,
      month: const YearMonth(2026, 12),
      limitAmount: 50000,
    );
    expect(
      (await budgets.getEffective(
        null,
        const YearMonth(2026, 11),
      ))?.limitAmount,
      30000,
    );
    expect(
      (await budgets.getEffective(null, const YearMonth(2027, 1)))?.limitAmount,
      50000,
    );
  });
}
