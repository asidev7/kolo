import 'package:flutter/widgets.dart';

/// Espacements (§2.2).
abstract final class KoloSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Marge horizontale standard d'un écran.
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: lg);
}

/// Rayons (§2.2).
abstract final class KoloRadii {
  static const double field = 8;
  static const double card = 16;
  static const double sheet = 24;

  static const BorderRadius fieldRadius = BorderRadius.all(
    Radius.circular(field),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
}

/// Zone tactile minimale (§2.2).
const double kMinTapTarget = 48;

/// Hauteur à réserver en bas d'une liste pour que son dernier élément reste
/// lisible au-dessus de la barre d'onglets floutée (`extendBody`).
///
/// La barre mesure 80 dp plus l'encoche basse du système, et cette hauteur est
/// justement celle que `extendBody` publie dans `MediaQuery.padding.bottom` :
/// réserver une constante fixe laisserait le dernier élément passer sous le
/// verre dès que le téléphone a une barre de navigation ou un geste système.
double bottomBarInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + KoloSpacing.lg;

/// Durée maximale des animations (§2.3).
const Duration kAnimationDuration = Duration(milliseconds: 220);

/// Durée d'animation effective : nulle si l'OS demande de réduire les
/// animations.
Duration animationDuration(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false
    ? Duration.zero
    : kAnimationDuration;
