import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';

/// Barre translucide : ce qui défile derrière elle apparaît flouté.
///
/// Utilisée pour la barre d'onglets du bas, posée par-dessus les écrans
/// (`Scaffold.extendBody`). L'application n'utilise qu'un seul flou, ce qui
/// reste léger pour les téléphones d'entrée de gamme.
class KoloFrostedBar extends StatelessWidget {
  const KoloFrostedBar({
    required this.child,
    super.key,
    this.blur = 16,
    this.opacity = 0.62,
  });

  final Widget child;

  /// Intensité du flou (sigma du filtre gaussien).
  final double blur;

  /// Opacité du voile posé sur le flou. Au-delà de 0,7 le contenu derrière
  /// la barre n'est plus perceptible et l'effet de verre dépoli disparaît ;
  /// en dessous de 0,5 les libellés perdent en lisibilité sur une liste
  /// colorée.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: KoloColors.surface.withValues(alpha: opacity),
            border: Border(
              top: BorderSide(
                color: KoloColors.border.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
