import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_card.dart';
import 'session_controller.dart';

/// Explication obligatoire avant le mode local (§3.C). Le texte est imposé
/// par la spécification : ne pas le reformuler.
const localModeWarning =
    'Tes données resteront uniquement sur ce téléphone. Si tu perds ou '
    'réinitialises ton téléphone, elles seront perdues. Tu pourras créer un '
    'compte plus tard pour les sauvegarder.';

class LocalModeScreen extends ConsumerStatefulWidget {
  const LocalModeScreen({super.key});

  @override
  ConsumerState<LocalModeScreen> createState() => _LocalModeScreenState();
}

class _LocalModeScreenState extends ConsumerState<LocalModeScreen> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      // Le routeur redirige vers le tableau de bord dès que la session change.
      await ref.read(sessionProvider.notifier).startLocalMode();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mode sans compte')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KoloSpacing.xl),
          children: [
            KoloCard(
              color: KoloColors.warningSoft,
              borderColor: KoloColors.warningSoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: KoloColors.warning,
                  ),
                  const SizedBox(width: KoloSpacing.md),
                  Expanded(
                    child: Text(
                      localModeWarning,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KoloSpacing.xl),
            Text(
              'Tu peux tout faire sans compte : saisir tes opérations, suivre '
              'ton budget et consulter tes statistiques. Aucune donnée '
              'n’est envoyée sur Internet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: KoloColors.textSecondary,
              ),
            ),
            const SizedBox(height: KoloSpacing.xxl),
            KoloButton(
              label: "J'ai compris, commencer",
              loading: _starting,
              onPressed: _start,
            ),
          ],
        ),
      ),
    );
  }
}
