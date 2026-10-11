import 'package:flutter/material.dart';

import '../../app/theme/kolo_typography.dart';

/// Logo KOLO (fichier fourni par le produit) et mention éditeur en texte
/// simple : on n'invente aucun logo ASITECH SOLUTION (§2.3).
class KoloLogo extends StatelessWidget {
  const KoloLogo({super.key, this.width = 180, this.showPublisher = false});

  final double width;
  final bool showPublisher;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/kolo_logo.png',
          width: width,
          semanticLabel: 'KOLO',
          // Le fichier source est large : on le décode à la taille affichée
          // pour ménager la mémoire des téléphones d'entrée de gamme.
          cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
        if (showPublisher) ...[
          const SizedBox(height: 4),
          const Text('By ASITECH SOLUTION', style: KoloTypography.caption),
        ],
      ],
    );
  }
}
