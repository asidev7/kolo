import 'package:drift/drift.dart';

import '../../core/model/enums.dart';

/// Conflits à résoudre (SYNC.md §5).
///
/// Un conflit naît quand le serveur a modifié un champ que le téléphone a
/// modifié de son côté depuis la version qu'il connaissait. L'enregistrement
/// local garde la version de l'utilisateur ; **la version du serveur est
/// conservée ici**, pour que l'écran « Conflits à résoudre » puisse montrer les
/// deux avant de trancher — sans elle, l'utilisateur choisirait à l'aveugle.
///
/// Un seul conflit par enregistrement et par compte : la clé primaire le
/// garantit, une nouvelle détection met la ligne à jour.
@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  TextColumn get userId => text()();

  TextColumn get entity => textEnum<SyncEntity>()();

  TextColumn get entityId => text()();

  /// `modified_on_server` ou `deleted_on_server` (champ `reason` de l'API).
  TextColumn get reason => text()();

  /// Version que le serveur détenait au moment du conflit : c'est le
  /// `base_version` du nouvel envoi si l'utilisateur garde sa version.
  IntColumn get serverVersion => integer()();

  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();

  /// Instantané serveur complet (JSON, clés de l'API).
  TextColumn get serverData => text()();

  /// Champs modifiés des deux côtés, en JSON.
  TextColumn get conflictingFields =>
      text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, entity, entityId};
}
