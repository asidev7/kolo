import 'package:flutter/material.dart';

/// Transition de page commune à toute l'application (§2.3).
///
/// Elle remplace les transitions par défaut de Material (glissement latéral
/// sur Android, depuis la droite sur iOS) par un fondu accompagné d'un très
/// léger glissement vers le haut, identique sur toutes les plateformes.
///
/// Le réglage système « réduire les animations » la neutralise : la page
/// s'affiche directement, sans mouvement.
Widget koloPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
    return child;
  }
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  // Mouvement court (3,5 % de la hauteur) : il accompagne le fondu sans
  // donner l'impression que la navigation traîne.
  final offset = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).animate(curved);
  final opacity = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.1, 1, curve: Curves.easeOut),
  );
  return FadeTransition(
    opacity: opacity,
    child: SlideTransition(position: offset, child: child),
  );
}

/// Applique la transition KOLO aux pages Material du thème.
class KoloPageTransitionsBuilder extends PageTransitionsBuilder {
  const KoloPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => koloPageTransition(context, animation, secondaryAnimation, child);
}
