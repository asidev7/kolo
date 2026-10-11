import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_logo.dart';

/// Écran d'accueil après l'onboarding : choix du mode d'utilisation (§3.C).
///
/// La création de compte et la connexion n'apparaissent que si une API est
/// configurée (`--dart-define=API_BASE_URL`) : sans serveur, un bouton
/// « Créer un compte » ne mènerait à rien (D20).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasBackend = ref.watch(appConfigProvider).hasBackend;
    return Scaffold(
      body: KoloAuroraBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(KoloSpacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - KoloSpacing.xl * 2,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      const KoloLogo(width: 200),
                      const SizedBox(height: KoloSpacing.xl),
                      Text(
                        'Ton argent. Tes décisions. Ton avenir.',
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: KoloSpacing.md),
                      Text(
                        'Enregistre tes revenus et tes dépenses, même sans '
                        'connexion.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: KoloColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      const SizedBox(height: KoloSpacing.xl),
                      if (hasBackend) ...[
                        KoloButton(
                          label: 'Créer un compte',
                          icon: Icons.person_add_alt_1_rounded,
                          onPressed: () => context.push(Routes.register),
                        ),
                        const SizedBox(height: KoloSpacing.md),
                        KoloButton(
                          label: "J'ai déjà un compte",
                          variant: KoloButtonVariant.secondary,
                          onPressed: () => context.push(Routes.login),
                        ),
                        const SizedBox(height: KoloSpacing.md),
                        KoloButton(
                          label: 'Commencer sans compte',
                          variant: KoloButtonVariant.text,
                          onPressed: () => context.push(Routes.localMode),
                        ),
                      ] else
                        KoloButton(
                          label: 'Commencer sans compte',
                          icon: Icons.phone_android_rounded,
                          onPressed: () => context.push(Routes.localMode),
                        ),
                      const SizedBox(height: KoloSpacing.lg),
                      const Text(
                        'By ASITECH SOLUTION',
                        style: TextStyle(
                          fontSize: 12,
                          color: KoloColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
