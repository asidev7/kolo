import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kolo/core/utils/money.dart';

import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('add-transaction')));
    await settle(tester);
    expect(find.text('Nouvelle opération'), findsOneWidget);
  }

  testWidgets('saisie d\'une dépense : enregistrée localement et affichée', (
    tester,
  ) async {
    final app = await TestApp.pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('amount-field')), '1500');
    await tester.pump();
    // Formatage des milliers pendant la saisie.
    expect(find.text('1${nbsp}500'), findsOneWidget);

    await tester.tap(find.text('Transport'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await settle(tester);

    expect(find.text('Opération enregistrée'), findsOneWidget);
    expect(await app.db.transactionsDao.countAlive(null), 1);
    // Le tableau de bord se met à jour depuis SQLite.
    expect(find.text('Transport'), findsOneWidget);
    expect(
      find.text('${minusSign}1${nbsp}500${nbsp}F${nbsp}CFA'),
      findsWidgets,
    );

    await app.dispose(tester);
  });

  testWidgets('montant vide et catégorie manquante : erreurs affichées, rien '
      'n\'est écrit', (tester) async {
    final app = await TestApp.pump(tester);
    await openForm(tester);

    await tester.tap(find.byKey(const Key('save-transaction')));
    await settle(tester);

    expect(find.text('Saisis un montant.'), findsOneWidget);
    expect(find.text('Choisis une catégorie.'), findsOneWidget);
    expect(await app.db.transactionsDao.countAlive(null), 0);

    await app.dispose(tester);
  });

  testWidgets('double appui sur Enregistrer : une seule opération', (
    tester,
  ) async {
    final app = await TestApp.pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('amount-field')), '2000');
    await tester.tap(find.text('Alimentation'));
    await tester.pump();

    final save = find.byKey(const Key('save-transaction'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await settle(tester);

    expect(await app.db.transactionsDao.countAlive(null), 1);
    await app.dispose(tester);
  });

  testWidgets('Annuler dans la snackbar supprime l\'opération', (tester) async {
    final app = await TestApp.pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('amount-field')), '500');
    await tester.tap(find.text('Alimentation'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await settle(tester);

    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect(await app.db.transactionsDao.countAlive(null), 0);

    await app.dispose(tester);
  });

  testWidgets('la dernière catégorie utilisée est présélectionnée', (
    tester,
  ) async {
    final app = await TestApp.pump(tester);
    await openForm(tester);
    await tester.enterText(find.byKey(const Key('amount-field')), '300');
    await tester.tap(find.text('Santé'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await settle(tester);
    // La snackbar d'annulation disparaît d'elle-même après 5 s.
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    await openForm(tester);
    await tester.enterText(find.byKey(const Key('amount-field')), '400');
    await tester.tap(find.byKey(const Key('save-transaction')));
    await settle(tester);

    final rows = await app.db.select(app.db.transactions).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.categoryId).toSet(), hasLength(1));

    await app.dispose(tester);
  });
}
