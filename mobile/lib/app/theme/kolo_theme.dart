import 'package:flutter/material.dart';

import 'kolo_colors.dart';
import 'kolo_page_transitions.dart';
import 'kolo_tokens.dart';
import 'kolo_typography.dart';

/// `ThemeData` unique de l'application. Mode clair seulement en v1, mais
/// tous les styles passent par ici pour permettre un mode sombre plus tard.
abstract final class KoloTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: KoloColors.primary,
      onPrimary: Colors.white,
      primaryContainer: KoloColors.primarySoft,
      onPrimaryContainer: KoloColors.primary,
      secondary: KoloColors.primary,
      onSecondary: Colors.white,
      error: KoloColors.negative,
      onError: Colors.white,
      surface: KoloColors.surface,
      onSurface: KoloColors.textPrimary,
      onSurfaceVariant: KoloColors.textSecondary,
      outline: KoloColors.border,
      outlineVariant: KoloColors.border,
    );

    final textTheme = KoloTypography.textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: KoloTypography.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: KoloColors.background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      // Même transition de page sur toutes les plateformes (§2.3).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: KoloPageTransitionsBuilder(),
          TargetPlatform.iOS: KoloPageTransitionsBuilder(),
          TargetPlatform.linux: KoloPageTransitionsBuilder(),
          TargetPlatform.macOS: KoloPageTransitionsBuilder(),
          TargetPlatform.windows: KoloPageTransitionsBuilder(),
          TargetPlatform.fuchsia: KoloPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: KoloColors.background,
        foregroundColor: KoloColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      cardTheme: const CardThemeData(
        color: KoloColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: KoloRadii.cardRadius,
          side: BorderSide(color: KoloColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: KoloColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: KoloColors.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: KoloSpacing.lg,
          vertical: KoloSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: KoloRadii.fieldRadius,
          borderSide: BorderSide(color: KoloColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: KoloRadii.fieldRadius,
          borderSide: BorderSide(color: KoloColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: KoloRadii.fieldRadius,
          borderSide: BorderSide(color: KoloColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: KoloRadii.fieldRadius,
          borderSide: BorderSide(color: KoloColors.negative),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: KoloRadii.fieldRadius,
          borderSide: BorderSide(color: KoloColors.negative, width: 1.5),
        ),
        hintStyle: TextStyle(color: KoloColors.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: KoloRadii.cardRadius,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, 52),
          foregroundColor: KoloColors.primary,
          side: const BorderSide(color: KoloColors.border),
          shape: const RoundedRectangleBorder(
            borderRadius: KoloRadii.cardRadius,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          foregroundColor: KoloColors.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: KoloColors.primary,
        foregroundColor: Colors.white,
        elevation: 1,
        shape: StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: KoloColors.surface,
        selectedColor: KoloColors.primarySoft,
        side: const BorderSide(color: KoloColors.border),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: KoloColors.textPrimary,
        ),
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: KoloColors.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KoloRadii.sheet),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KoloColors.surface,
        indicatorColor: KoloColors.primarySoft,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: KoloColors.textPrimary,
        actionTextColor: KoloColors.primarySoft,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: KoloColors.primary,
        linearTrackColor: KoloColors.primarySoft,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: KoloColors.primarySoft,
          selectedForegroundColor: KoloColors.primary,
          side: const BorderSide(color: KoloColors.border),
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        ),
      ),
    );
  }
}
