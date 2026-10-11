import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/network/connectivity.dart';
import '../core/widgets/frosted_bar.dart';
import '../core/widgets/offline_banner.dart';
import '../features/auth/presentation/session_controller.dart';

/// Structure à onglets : Accueil, Historique, Statistiques, Profil.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // En mode local le réseau n'est jamais nécessaire : pas de bandeau.
    final isAccount = ref.watch(sessionProvider).value?.isAccount ?? false;
    final offline = isAccount && (ref.watch(isOfflineProvider).value ?? false);

    return Scaffold(
      // Le corps passe sous la barre d'onglets : elle le floute, et la
      // dernière ligne d'une liste reste visible sous la barre translucide.
      extendBody: true,
      body: Column(
        children: [
          SafeArea(bottom: false, child: OfflineBanner(visible: offline)),
          Expanded(
            // Un `Builder` pour lire la `MediaQuery` posée par `extendBody`
            // (elle porte la hauteur de la barre d'onglets, dont les écrans
            // se servent pour remonter leur bouton flottant). `removePadding`
            // retire les quatre côtés par défaut : on ne touche qu'au haut,
            // occupé par le bandeau.
            child: Builder(
              builder: (innerContext) => MediaQuery.removePadding(
                context: innerContext,
                removeTop: offline,
                removeLeft: false,
                removeRight: false,
                removeBottom: false,
                child: shell,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: KoloFrostedBar(
        child: NavigationBarTheme(
          // Fond transparent : c'est le contenu flouté du dessous qui donne
          // sa teinte à la barre.
          data: const NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) => shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Historique',
              ),
              NavigationDestination(
                icon: Icon(Icons.pie_chart_outline_rounded),
                selectedIcon: Icon(Icons.pie_chart_rounded),
                label: 'Statistiques',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
