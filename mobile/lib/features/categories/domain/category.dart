import 'package:meta/meta.dart';

import '../../../core/model/enums.dart';

/// Catégorie telle que vue par l'interface.
@immutable
class KoloCategory {
  const KoloCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.isDefault,
    required this.isArchived,
    this.color,
    this.userId,
  });

  final String id;
  final String name;
  final TransactionType type;
  final String icon;
  final String? color;
  final bool isDefault;

  /// Archivée (`deleted_at` non nul) : n'est plus proposée à la saisie mais
  /// reste affichée sur les anciennes opérations (§3.G).
  final bool isArchived;
  final String? userId;

  @override
  bool operator ==(Object other) =>
      other is KoloCategory &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.icon == icon &&
      other.color == color &&
      other.isDefault == isDefault &&
      other.isArchived == isArchived &&
      other.userId == userId;

  @override
  int get hashCode =>
      Object.hash(id, name, type, icon, color, isDefault, isArchived, userId);
}

/// Règles de saisie d'une catégorie personnalisée.
abstract final class CategoryRules {
  static const int maxNameLength = 40;

  /// Retourne un message d'erreur, ou `null` si le nom est valide.
  static String? validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Donne un nom à la catégorie.';
    if (trimmed.length > maxNameLength) {
      return 'Le nom ne doit pas dépasser $maxNameLength caractères.';
    }
    return null;
  }
}
