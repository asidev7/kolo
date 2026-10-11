import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/kolo_tokens.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/kolo_entrance.dart';
import '../../../core/widgets/kolo_logo.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/session_controller.dart';

/// Écran de démarrage (§3.A).
///
/// Il n'attend que l'ouverture de la base et la lecture de la session ; le
/// routeur redirige dès que la session est chargée. Aucun appel réseau.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: KoloAuroraBackground(
        child: SafeArea(
          child: Center(
            child: KoloEntrance(
              child: session.hasError
                  ? ErrorState(
                      error: session.error!,
                      onRetry: () =>
                          ref.read(sessionProvider.notifier).reload(),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KoloLogo(width: 200, showPublisher: true),
                        SizedBox(height: KoloSpacing.xxl),
                        SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
