import 'package:drift/drift.dart';

import '../../../core/errors/failures.dart';
import '../../../core/model/enums.dart';
import '../../../core/utils/time_source.dart';
import '../../../database/app_database.dart';
import '../../../synchronization/outbox/outbox_planner.dart';
import '../../../synchronization/outbox/outbox_writer.dart';
import '../../../synchronization/wire/payloads.dart';
import '../domain/category.dart';

KoloCategory categoryFromRow(CategoryRow row) => KoloCategory(
  id: row.id,
  name: row.name,
  type: row.type,
  icon: row.icon,
  color: row.color,
  isDefault: row.isDefault,
  isArchived: row.deletedAt != null,
  userId: row.userId,
);

class CategoriesRepository {
  CategoriesRepository({
    required this._db,
    required this._writer,
    required this._time,
    required this._ids,
  });

  final AppDatabase _db;
  final OutboxWriter _writer;
  final TimeSource _time;
  final IdGenerator _ids;

  Stream<List<KoloCategory>> watchActive(
    String? ownerId, {
    TransactionType? type,
  }) => _db.categoriesDao
      .watchActive(ownerId, type: type)
      .map((rows) => rows.map(categoryFromRow).toList());

  /// Index id → catégorie, archivées comprises (affichage de l'historique).
  Stream<Map<String, KoloCategory>> watchLookup(String? ownerId) => _db
      .categoriesDao
      .watchAllVisible(ownerId)
      .map((rows) => {for (final r in rows) r.id: categoryFromRow(r)});

  Future<KoloCategory?> findById(String id) async {
    final row = await _db.categoriesDao.findById(id);
    return row == null ? null : categoryFromRow(row);
  }

  /// Crée une catégorie personnalisée (nom + icône + type, §3.G).
  Future<KoloCategory> createCustom({
    required String? ownerId,
    required String name,
    required TransactionType type,
    required String icon,
  }) async {
    final nameError = CategoryRules.validateName(name);
    if (nameError != null) throw ValidationFailure({'name': nameError});
    final trimmed = name.trim();

    try {
      return await _writer.transaction((outbox) async {
        final homonym = await _db.categoriesDao.findActiveByName(
          ownerId,
          type,
          trimmed,
        );
        if (homonym != null) {
          throw const ValidationFailure({
            'name': 'Une catégorie porte déjà ce nom.',
          });
        }
        final now = _time.nowUtc();
        final row = CategoryRow(
          id: _ids(),
          userId: ownerId,
          name: trimmed,
          type: type,
          icon: icon,
          isDefault: false,
          sortOrder: 500,
          createdAt: now,
          updatedAt: now,
          version: 0,
          syncStatus: ownerId == null
              ? SyncStatus.localOnly
              : SyncStatus.pending,
        );
        await _db.into(_db.categories).insert(row);
        if (ownerId != null) {
          final payload = Payloads.category(row);
          await outbox.record(
            OutboxRequest(
              entity: SyncEntity.category,
              entityId: row.id,
              opType: OutboxOpType.upsert,
              payload: payload,
              changedFields: payload.keys.toSet(),
              baseVersion: 0,
              userId: ownerId,
            ),
          );
        }
        return categoryFromRow(row);
      });
    } on Failure {
      rethrow;
    } on Object {
      // Course rare : l'index unique a refusé un homonyme inséré entre-temps.
      // On vérifie plutôt que de dépendre du type d'exception du moteur
      // SQLite, qui varie selon la plateforme.
      final homonym = await _db.categoriesDao.findActiveByName(
        ownerId,
        type,
        trimmed,
      );
      if (homonym == null) rethrow;
      throw const ValidationFailure({
        'name': 'Une catégorie porte déjà ce nom.',
      });
    }
  }

  /// Archive une catégorie personnalisée. Une catégorie n'est jamais
  /// supprimée physiquement : les anciennes opérations l'affichent encore.
  Future<void> archive({required String? ownerId, required String id}) =>
      _writer.transaction((outbox) async {
        final row = await _db.categoriesDao.findById(id);
        if (row == null || row.deletedAt != null) return;
        if (row.isDefault || row.userId != ownerId) {
          throw const ForbiddenFailure(
            'Les catégories par défaut ne peuvent pas être archivées.',
          );
        }
        final now = _time.nowUtc();
        await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
          CategoriesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            syncStatus: Value(
              ownerId == null ? SyncStatus.localOnly : SyncStatus.pending,
            ),
          ),
        );
        if (ownerId != null) {
          await outbox.record(
            OutboxRequest(
              entity: SyncEntity.category,
              entityId: id,
              opType: OutboxOpType.delete,
              payload: const {},
              changedFields: const {},
              baseVersion: row.version,
              userId: ownerId,
            ),
          );
        }
      });
}
