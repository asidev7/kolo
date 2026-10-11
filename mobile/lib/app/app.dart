import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'sync.dart';
import 'theme/kolo_theme.dart';

/// Messager global : une snackbar (« Opération enregistrée — Annuler »)
/// survit à la fermeture de l'écran qui l'a déclenchée.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

class KoloApp extends ConsumerWidget {
  const KoloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Créé ici, une fois pour toutes : le coordonnateur de synchronisation
    // doit vivre aussi longtemps que l'application, quel que soit l'écran
    // affiché (il réagit à l'écriture locale et au retour au premier plan).
    ref.watch(syncCoordinatorProvider);

    return MaterialApp.router(
      title: 'KOLO',
      debugShowCheckedModeBanner: false,
      theme: KoloTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
      scaffoldMessengerKey: rootMessengerKey,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
