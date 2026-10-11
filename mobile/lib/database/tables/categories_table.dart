import 'package:drift/drift.dart';

import '../../core/model/enums.dart';
import 'sync_columns.dart';

/// Catégories par défaut (UUID fixes partagés avec le serveur) et
/// personnalisées (§5.4).
///
/// Unicité `(user_id, type, nom)` hors catégories archivées, insensible à la
/// casse. `COALESCE` est nécessaire car SQLite considère deux `NULL` comme
/// distincts dans un index unique.
@DataClassName('CategoryRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX categories_owner_type_name '
  "ON categories (COALESCE(user_id, ''), type, lower(name)) "
  'WHERE deleted_at IS NULL',
)
class Categories extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 40)();

  TextColumn get type => textEnum<TransactionType>()();

  /// Clé d'icône (voir `CategoryIcon`), jamais un chemin de fichier.
  TextColumn get icon => text()();

  /// Couleur optionnelle au format `#RRGGBB`.
  TextColumn get color => text().nullable()();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
