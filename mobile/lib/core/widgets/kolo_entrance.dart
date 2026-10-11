import 'package:flutter/material.dart';

/// Entrée en fondu et léger glissement, décalée dans le temps.
///
/// `index` retarde le départ de l'animation pour donner un effet d'escalier
/// aux blocs d'un même écran (0 = premier bloc). L'animation ne joue qu'une
/// fois, à l'apparition du bloc.
///
/// Le réglage système « réduire les animations » la neutralise : le contenu
/// apparaît directement.
class KoloEntrance extends StatelessWidget {
  const KoloEntrance({required this.child, super.key, this.index = 0});

  final Widget child;
  final int index;

  static const _duration = Duration(milliseconds: 420);

  /// Part du temps total laissée vide avant le départ de chaque bloc.
  static const _step = 0.07;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return child;
    }
    final start = (index * _step).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _duration,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
