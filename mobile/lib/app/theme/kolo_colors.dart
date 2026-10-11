import 'package:flutter/painting.dart';

/// Palette KOLO (§2.1). Aucune couleur ne doit être codée en dur ailleurs :
/// passer par ces jetons ou par le `ThemeData`.
abstract final class KoloColors {
  /// Bleu cobalt — actions principales, solde.
  static const primary = Color(0xFF1749C7);

  /// Fonds de cartes, chips sélectionnés.
  static const primarySoft = Color(0xFFEAF1FF);

  /// Revenus, budget sain.
  static const positive = Color(0xFF16A34A);

  /// Dépenses, alertes, dépassement.
  static const negative = Color(0xFFDC2626);

  /// Seuil d'alerte budget.
  static const warning = Color(0xFFD97706);

  static const background = Color(0xFFF7F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  /// Teintes douces dérivées, pour les fonds d'icônes et de bandeaux.
  static const positiveSoft = Color(0xFFE8F6EE);
  static const negativeSoft = Color(0xFFFDECEC);
  static const warningSoft = Color(0xFFFDF3E6);

  /// Couleurs des séries de graphiques (catégories), ordre stable.
  static const chart = <Color>[
    Color(0xFF1749C7),
    Color(0xFF0EA5E9),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0F766E),
    Color(0xFF64748B),
  ];
}
