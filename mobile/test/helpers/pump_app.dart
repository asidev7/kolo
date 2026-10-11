import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/app/app.dart';
import 'package:kolo/app/providers.dart';
import 'package:kolo/core/providers/core_providers.dart';
import 'package:kolo/database/app_database.dart';
import 'package:kolo/features/budgets/data/budget_notifier.dart';
import 'package:kolo/features/settings/data/settings_keys.dart';

import 'fakes.dart';
import 'test_database.dart';

/// Notificateur qui mémorise au lieu d'afficher.
class RecordingNotifier implements LocalNotifier {
  final shown = <({int id, String title, String body})>[];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async => shown.add((id: id, title: title, body: body));

  @override
  Future<bool> requestPermission() async => true;
}

/// Contexte d'un test d'application complète, en mode local.
class TestApp {
  TestApp._(this.db, this.time, this.notifier);

  final AppDatabase db;
  final FakeTime time;
  final RecordingNotifier notifier;

  static Future<TestApp> pump(
    WidgetTester tester, {
    bool onboardingSeen = true,
    bool localMode = true,
  }) async {
    final db = newTestDatabase();
    final time = FakeTime(DateTime(2026, 10, 9, 12));
    final notifier = RecordingNotifier();
    if (onboardingSeen) {
      await db.settingsDao.write(SettingsKeys.onboardingSeen, 'true');
    }
    if (localMode) {
      await db.settingsDao.write(SettingsKeys.sessionMode, 'local');
    }

    // Téléphone d'entrée de gamme typique : 360 × 780 dp.
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          timeSourceProvider.overrideWithValue(time.source),
          localNotifierProvider.overrideWithValue(notifier),
        ],
        child: const KoloApp(),
      ),
    );
    await settle(tester);
    return TestApp._(db, time, notifier);
  }

  /// Démonte l'application puis ferme la base (aucun stream en suspens).
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }
}

/// `pumpAndSettle` borné : les requêtes Drift se résolvent en microtâches,
/// quelques images suffisent.
Future<void> settle(WidgetTester tester) async {
  // Couvre aussi les transitions de page (≈ 300 ms).
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
