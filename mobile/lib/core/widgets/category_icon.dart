import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';

/// Correspondance clé d'icône → glyphe. Un seul jeu d'icônes : Material
/// Icons « Rounded » (§2.3). Les clés sont stockées en base et partagées
/// avec le serveur : en ajouter est sans risque, en renommer non.
abstract final class CategoryIcons {
  static const Map<String, IconData> byKey = {
    'food': Icons.restaurant_rounded,
    'transport': Icons.directions_bus_rounded,
    'home': Icons.home_rounded,
    'school': Icons.school_rounded,
    'health': Icons.local_hospital_rounded,
    'phone': Icons.smartphone_rounded,
    'leisure': Icons.sports_esports_rounded,
    'bills': Icons.receipt_long_rounded,
    'salary': Icons.work_rounded,
    'freelance': Icons.handyman_rounded,
    'scholarship': Icons.workspace_premium_rounded,
    'family': Icons.family_restroom_rounded,
    'sale': Icons.storefront_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'clothes': Icons.checkroom_rounded,
    'gift': Icons.card_giftcard_rounded,
    'savings': Icons.savings_rounded,
    'church': Icons.volunteer_activism_rounded,
    'beauty': Icons.content_cut_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'water': Icons.water_drop_rounded,
    'power': Icons.bolt_rounded,
    'child': Icons.child_care_rounded,
    'sport': Icons.fitness_center_rounded,
    'other': Icons.more_horiz_rounded,
  };

  /// Icônes proposées à la création d'une catégorie personnalisée.
  static const List<String> selectable = [
    'food', 'transport', 'home', 'school', 'health', 'phone', 'leisure', //
    'bills', 'shopping', 'clothes', 'gift', 'savings', 'church', 'beauty',
    'fuel', 'water', 'power', 'child', 'sport', 'salary', 'freelance',
    'scholarship', 'family', 'sale', 'other',
  ];

  static IconData of(String key) => byKey[key] ?? Icons.label_rounded;
}

/// Pastille ronde d'une catégorie.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    required this.iconKey,
    super.key,
    this.size = 40,
    this.color,
    this.background,
  });

  final String iconKey;
  final double size;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? KoloColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: Icon(
          CategoryIcons.of(iconKey),
          size: size * 0.5,
          color: color ?? KoloColors.primary,
        ),
      ),
    );
  }
}
