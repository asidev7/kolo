import 'package:flutter/material.dart';

import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import 'privacy_text.dart';

/// Politique de confidentialité, embarquée dans l'application (§3.J).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KoloSpacing.lg),
          children: [
            for (final (title, body) in privacyPolicySections) ...[
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: KoloColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: KoloSpacing.xs),
              Text(body, style: theme.textTheme.bodyMedium),
              const SizedBox(height: KoloSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }
}
