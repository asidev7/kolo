import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/money.dart';
import 'package:kolo/core/utils/text_normalize.dart';
import 'package:kolo/database/app_database.dart';

import '../helpers/pump_app.dart';

final food = DefaultCategories.all[0].id;
final transport = DefaultCategories.all[1].id;
final salary = DefaultCategories.all
    .firstWhere((c) => c.type == TransactionType.income)
    .id;

Future<void> seed(
  AppDatabase db, {
  required String id,
  required int amount,
  required String on,
  String? category,
  TransactionType type = TransactionType.expense,
  String? note,
}) async {
  final at = DateTime.utc(2026, 10, 9, 8, 0, id.hashCode % 60);
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          id: id,
          type: type,
          amount: amount,
          categoryId:
              category ?? (type == TransactionType.income ? salary : food),
          note: Value(note),
          noteSearch: Value(note == null ? null : normalizeForSearch(note)),
          occurredOn: on,
          createdAt: at,
          updatedAt: at,
          syncStatus: SyncStatus.localOnly,
        ),
      );
}

String money(int v) => formatMoney(v);

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('tableau de bord', () {
    testWidgets('état vide explicite', (tester) async {
      final app = await TestApp.pump(tester);
      expect(find.text('Bonjour'), findsOneWidget);
      expect(find.text('Solde net enregistré'), findsOneWidget);
      expect(find.text('Aucune opération'), findsOneWidget);
      expect(find.text('Aucun budget défini'), findsOneWidget);
      expect(find.text('Mode local'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('solde net, totaux du mois et dernières opérations', (
      tester,
    ) async {
      final app = await TestApp.pump(tester);
      await seed(
        app.db,
        id: 'a',
        amount: 50000,
        on: '2026-10-01',
        type: TransactionType.income,
      );
      await seed(app.db, id: 'b', amount: 12500, on: '2026-10-05');
      await seed(app.db, id: 'c', amount: 3000, on: '2026-09-20');
      await settle(tester);

      final balance = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('net-balance')),
          matching: find.byType(Text),
        ),
      );
      expect(balance.data, money(34500));
      expect(find.text(money(50000)), findsWidgets); // revenus du mois
      expect(find.text(money(12500)), findsWidgets); // dépenses du mois
      expect(find.text('Dernières opérations'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('historique', () {
    Future<TestApp> openHistory(WidgetTester tester) async {
      final app = await TestApp.pump(tester);
      await seed(app.db, id: 'a', amount: 1000, on: '2026-10-09', note: 'Zém');
      await seed(
        app.db,
        id: 'b',
        amount: 2000,
        on: '2026-10-09',
        category: transport,
      );
      await seed(
        app.db,
        id: 'c',
        amount: 40000,
        on: '2026-10-08',
        type: TransactionType.income,
      );
      await tester.tap(find.text('Historique').last);
      await settle(tester);
      return app;
    }

    testWidgets('groupé par jour avec total du jour', (tester) async {
      final app = await openHistory(tester);
      expect(find.text("Aujourd'hui"), findsOneWidget);
      expect(find.text('Hier'), findsOneWidget);
      expect(find.text(money(-3000)), findsOneWidget);
      expect(find.text('+${money(40000)}'), findsWidgets);
      await app.dispose(tester);
    });

    testWidgets('recherche dans les notes', (tester) async {
      final app = await openHistory(tester);
      await tester.enterText(find.byType(TextField), 'zém');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.text('Zém'), findsOneWidget);
      expect(find.text('Transport'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('filtre par type, puis réinitialisation', (tester) async {
      final app = await openHistory(tester);
      await tester.tap(find.text('Tous les types'));
      await settle(tester);
      await tester.tap(find.text('Revenus').last);
      await settle(tester);
      expect(find.text('Salaire'), findsOneWidget);
      expect(find.text('Transport'), findsNothing);

      // La puce est au bout d'une rangée défilante sur un écran de 360 dp.
      await tester.ensureVisible(find.text('Réinitialiser'));
      await tester.tap(find.text('Réinitialiser'));
      await settle(tester);
      expect(find.text('Transport'), findsOneWidget);
      await app.dispose(tester);
    });
  });
}
