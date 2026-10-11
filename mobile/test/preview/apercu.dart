// Outil d'aperçu visuel, **hors CI** : le nom ne finit pas par `_test.dart`,
// donc `flutter test` l'ignore. Il sert à regarder le rendu réel (pixels) du
// flou de la barre d'onglets et des animations de page :
//
//     flutter test --update-goldens test/preview/apercu.dart
//
// puis à ouvrir les images de `test/preview/`. Les images sont régénérées à
// chaque exécution : ne pas s'en servir comme test de non-régression (elles
// dépendent de la plateforme de rendu).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kolo/core/constants/default_categories.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/text_normalize.dart';
import 'package:kolo/database/app_database.dart';

import '../helpers/pump_app.dart';

/// Quelques opérations pour que les cartes et la liste soient remplies.
Future<void> seedPreview(TestApp app) async {
  final food = DefaultCategories.all[0].id;
  final transport = DefaultCategories.all[1].id;
  final salary = DefaultCategories.all
      .firstWhere((c) => c.type == TransactionType.income)
      .id;

  Future<void> add(
    String id,
    String on,
    int amount, {
    TransactionType type = TransactionType.expense,
    String? category,
    String? note,
  }) async {
    final at = DateTime.utc(2026, 10, 9, 8, id.hashCode % 60);
    await app.db
        .into(app.db.transactions)
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

  await add('a', '2026-10-01', 250000, type: TransactionType.income);
  await add('b', '2026-10-03', 12500, note: 'Marché');
  await add('c', '2026-10-05', 6000, category: transport, note: 'Taxi');
  await add('d', '2026-10-06', 3500, note: 'Pain');
  await add('e', '2026-10-07', 22000, category: transport, note: 'Essence');
  await add('f', '2026-10-08', 4500, note: 'Eau');
  await add('g', '2026-10-08', 15000, note: 'Pharmacie');
  await add('h', '2026-10-09', 8000, note: 'Crédit téléphone');
  // Une liste longue, pour voir les lignes passer sous la barre floutée.
  const extras = [
    'Boulangerie',
    'Taxi',
    'Marché',
    'Essence',
    'Pharmacie',
    'Crédit',
    'Riz et huile',
    'Transport',
    'Savon',
    'Moto-taxi',
    'Électricité',
    'Internet',
  ];
  for (var i = 0; i < extras.length; i++) {
    await add(
      'x$i',
      i.isEven ? '2026-10-09' : '2026-10-08',
      1000 + i * 750,
      category: i.isEven ? food : transport,
      note: extras[i],
    );
  }
}

/// Barre de navigation Android de 24 dp (72 px physiques, DPR 3).
void withSystemBar(WidgetTester tester) {
  tester.view
    ..padding = const FakeViewPadding(bottom: 72)
    ..viewPadding = const FakeViewPadding(bottom: 72);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  testWidgets('aperçu accueil — flou de la barre d\'onglets', (tester) async {
    final app = await TestApp.pump(tester);
    await seedPreview(app);
    await settle(tester);

    // Amène les opérations franchement derrière la barre floutée.
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('accueil.png'),
    );
    await app.dispose(tester);
  });

  testWidgets('aperçu accueil — avec barre système', (tester) async {
    withSystemBar(tester);
    final app = await TestApp.pump(tester);
    await seedPreview(app);
    await settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('accueil_systeme.png'),
    );
    await app.dispose(tester);
  });

  testWidgets('aperçu historique — lignes sous la barre floutée', (
    tester,
  ) async {
    final app = await TestApp.pump(tester);
    await seedPreview(app);
    await settle(tester);

    await tester.tap(find.text('Historique'));
    await settle(tester);
    // Défilement au milieu de la liste : des lignes passent sous la barre.
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('historique.png'),
    );
    await app.dispose(tester);
  });

  testWidgets('aperçu transition de page', (tester) async {
    final app = await TestApp.pump(tester);
    await settle(tester);

    // Onglet Profil, puis une sous-page (transition KOLO : 220 ms).
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.text('Budget du mois'));
    await tester.pump(); // démarre la transition
    await tester.pump(const Duration(milliseconds: 40)); // début
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('transition_debut.png'),
    );
    await tester.pump(const Duration(milliseconds: 60)); // milieu
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('transition_milieu.png'),
    );
    await app.dispose(tester);
  });

  testWidgets('aperçu écran d\'entrée', (tester) async {
    final app = await TestApp.pump(tester, localMode: false);
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('bienvenue.png'),
    );
    await app.dispose(tester);
  });
}
