import '../model/enums.dart';

/// Définition immuable d'une catégorie par défaut.
class DefaultCategory {
  const DefaultCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final TransactionType type;
  final String icon;
  final int sortOrder;
}

/// Catégories par défaut (§3.G).
///
/// **Ces UUID sont un contrat avec le serveur** : ils sont recopiés à
/// l'identique dans la data migration Django
/// `backend/apps/categories/migrations/0002_default_categories.py`.
/// Ne jamais les modifier ni les réutiliser ; pour retirer une catégorie,
/// l'archiver.
abstract final class DefaultCategories {
  static const List<DefaultCategory> all = [
    // Dépenses
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000001',
      name: 'Alimentation',
      type: TransactionType.expense,
      icon: 'food',
      sortOrder: 10,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000002',
      name: 'Transport',
      type: TransactionType.expense,
      icon: 'transport',
      sortOrder: 20,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000003',
      name: 'Logement',
      type: TransactionType.expense,
      icon: 'home',
      sortOrder: 30,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000004',
      name: 'Études',
      type: TransactionType.expense,
      icon: 'school',
      sortOrder: 40,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000005',
      name: 'Santé',
      type: TransactionType.expense,
      icon: 'health',
      sortOrder: 50,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000006',
      name: 'Communication',
      type: TransactionType.expense,
      icon: 'phone',
      sortOrder: 60,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000007',
      name: 'Loisirs',
      type: TransactionType.expense,
      icon: 'leisure',
      sortOrder: 70,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000008',
      name: 'Factures',
      type: TransactionType.expense,
      icon: 'bills',
      sortOrder: 80,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000009',
      name: 'Autres',
      type: TransactionType.expense,
      icon: 'other',
      sortOrder: 990,
    ),
    // Revenus
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000101',
      name: 'Salaire',
      type: TransactionType.income,
      icon: 'salary',
      sortOrder: 10,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000102',
      name: 'Activité indépendante',
      type: TransactionType.income,
      icon: 'freelance',
      sortOrder: 20,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000103',
      name: 'Bourse',
      type: TransactionType.income,
      icon: 'scholarship',
      sortOrder: 30,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000104',
      name: 'Aide familiale',
      type: TransactionType.income,
      icon: 'family',
      sortOrder: 40,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000105',
      name: 'Vente',
      type: TransactionType.income,
      icon: 'sale',
      sortOrder: 50,
    ),
    DefaultCategory(
      id: 'c0a7e9e0-0000-4000-8000-000000000106',
      name: 'Autres',
      type: TransactionType.income,
      icon: 'other',
      sortOrder: 990,
    ),
  ];

  /// Horodatage fixe des catégories par défaut : identique sur tous les
  /// appareils, il ne dépend jamais de l'horloge du téléphone.
  static final DateTime createdAt = DateTime.utc(2026, 1, 1);
}
