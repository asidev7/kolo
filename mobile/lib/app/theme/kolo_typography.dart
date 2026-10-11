import 'package:flutter/material.dart';

import 'kolo_colors.dart';

/// Échelle typographique (§2.2) : display 32 / title 22 / subtitle 17 /
/// body 15 / caption 13. Police Inter embarquée.
abstract final class KoloTypography {
  static const String fontFamily = 'Inter';

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: KoloColors.textPrimary,
    fontFeatures: tabular,
  );

  static const title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: KoloColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: KoloColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: KoloColors.textPrimary,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: KoloColors.textSecondary,
  );

  /// Montants : chiffres tabulaires pour un alignement vertical stable.
  static const amount = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: KoloColors.textPrimary,
    fontFeatures: tabular,
  );

  static TextTheme get textTheme => TextTheme(
    displaySmall: display,
    headlineSmall: title,
    titleLarge: title,
    titleMedium: subtitle,
    titleSmall: subtitle.copyWith(fontSize: 15),
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: body.copyWith(fontWeight: FontWeight.w600),
    labelMedium: caption.copyWith(fontWeight: FontWeight.w500),
    labelSmall: caption.copyWith(fontSize: 12),
  );
}
