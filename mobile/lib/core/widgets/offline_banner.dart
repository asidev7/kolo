import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';
import '../../app/theme/kolo_tokens.dart';

/// Bandeau hors ligne global, **non bloquant** (§2.3) : toutes les
/// fonctionnalités locales restent utilisables.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.visible, super.key});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: animationDuration(context),
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: KoloColors.warningSoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: KoloSpacing.lg,
                  vertical: KoloSpacing.sm,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: KoloColors.warning,
                    ),
                    SizedBox(width: KoloSpacing.sm),
                    Expanded(
                      child: Text(
                        'Hors ligne — tes opérations restent enregistrées '
                        'sur ce téléphone.',
                        style: TextStyle(
                          fontSize: 13,
                          color: KoloColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
