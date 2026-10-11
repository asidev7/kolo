import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';
import '../../app/theme/kolo_tokens.dart';
import '../errors/failures.dart';
import 'kolo_button.dart';

/// État « chargement » (§2.3).
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Chargement…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: label,
        liveRegion: true,
        child: const Padding(
          padding: EdgeInsets.all(KoloSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// État « vide » : toujours une explication et, si possible, une action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? KoloSpacing.lg : KoloSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: const BoxDecoration(
                color: KoloColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: KoloColors.primary,
                size: compact ? 24 : 32,
              ),
            ),
            const SizedBox(height: KoloSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoloSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: KoloSpacing.lg),
              KoloButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// État « erreur » avec action « Réessayer » (§2.3). N'affiche jamais de
/// détail technique.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoloSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: KoloColors.negative,
              size: 40,
            ),
            const SizedBox(height: KoloSpacing.md),
            Text(
              userMessageFor(error),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoloSpacing.lg),
            KoloButton(
              label: 'Réessayer',
              icon: Icons.refresh_rounded,
              variant: KoloButtonVariant.secondary,
              onPressed: onRetry,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}
