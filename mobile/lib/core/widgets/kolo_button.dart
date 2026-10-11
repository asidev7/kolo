import 'package:flutter/material.dart';

enum KoloButtonVariant { primary, secondary, text, danger }

/// Bouton standard. Pendant [loading], le bouton est désactivé : c'est la
/// première barrière contre la double soumission.
class KoloButton extends StatelessWidget {
  const KoloButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = KoloButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final KoloButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final callback = loading ? null : onPressed;
    final child = loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == KoloButtonVariant.primary
                  ? scheme.onPrimary
                  : scheme.primary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );

    final button = switch (variant) {
      KoloButtonVariant.primary => FilledButton(
        onPressed: callback,
        child: child,
      ),
      KoloButtonVariant.danger => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        child: child,
      ),
      KoloButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        child: child,
      ),
      KoloButtonVariant.text => TextButton(onPressed: callback, child: child),
    };

    return Semantics(
      button: true,
      enabled: callback != null,
      label: loading ? '$label, en cours' : null,
      excludeSemantics: loading,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
