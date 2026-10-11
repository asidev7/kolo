import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';

/// Fond des pages d'entrée : deux halos de couleur très diffus.
///
/// Les halos sont peints avec des dégradés radiaux, pas avec un flou GPU :
/// l'effet « flouté » ne coûte rien et reste net sur les petits écrans.
class KoloAuroraBackground extends StatelessWidget {
  const KoloAuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KoloColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -140,
            right: -110,
            child: _Halo(color: KoloColors.primary, size: 340, opacity: 0.16),
          ),
          const Positioned(
            bottom: -170,
            left: -130,
            child: _Halo(color: KoloColors.positive, size: 380, opacity: 0.12),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
