import 'package:drift/drift.dart';

import '../../core/model/enums.dart';
import '../app_database.dart';
import '../tables/categories_table.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.attachedDatabase);

  /// Catégories proposées à la saisie : par défaut + personnalisées du
  /// propriétaire, hors archivées.
  Stream<List<CategoryRow>> watchActive(
    String? userId, {
    TransactionType? type,
  }) {
    final stmt = select(categories)
      ..where((c) {
        var e = c.deletedAt.isNull() & _visibleTo(c, userId);
        if (type != null) e = e & c.type.equalsValue(type);
        return e;
      })
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    return stmt.watch();
  }

  /// Toutes les catégories visibles, **archivées comprises** : une ancienne
  /// opération doit toujours pouvoir afficher sa catégorie (§3.G).
  Stream<List<CategoryRow>> watchAllVisible(String? userId) =>
      (select(categories)..where((c) => _visibleTo(c, userId))).watch();

  Future<CategoryRow?> findById(String id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Recherche d'un homonyme actif (comparaison insensible à la casse).
  Future<CategoryRow?> findActiveByName(
    String? userId,
    TransactionType type,
    String name,
  ) =>
      (select(categories)
            ..where(
              (c) =>
                  c.deletedAt.isNull() &
                  _visibleTo(c, userId) &
                  c.type.equalsValue(type) &
                  c.name.lower().equals(name.trim().toLowerCase()),
            )
            ..limit(1))
          .getSingleOrNull();

  Expression<bool> _visibleTo($CategoriesTable c, String? userId) =>
      c.isDefault.equals(true) | ownedBy(c.userId, userId);
}
