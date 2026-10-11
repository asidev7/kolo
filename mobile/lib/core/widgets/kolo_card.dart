import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';
import '../../app/theme/kolo_tokens.dart';

/// Carte sobre à coins arrondis, sans ombre (§2.2).
class KoloCard extends StatelessWidget {
  const KoloCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(KoloSpacing.lg),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? KoloColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: KoloRadii.cardRadius,
        side: BorderSide(color: borderColor ?? KoloColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
