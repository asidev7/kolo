import 'package:drift/drift.dart';

import '../../core/model/enums.dart';
import '../app_database.dart';
import '../tables/sync_conflicts_table.dart';

part 'sync_conflicts_dao.g.dart';

/// Lecture et écriture des conflits à résoudre (SYNC.md §5).
@DriftAccessor(tables: [SyncConflicts])
class SyncConflictsDao extends DatabaseAccessor<AppDatabase>
    with _$SyncConflictsDaoMixin {
  SyncConflictsDao(super.attachedDatabase);

  Stream<List<SyncConflictRow>> watchAll(String userId) =>
      (select(syncConflicts)
            ..where((c) => c.userId.equals(userId))
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .watch();

  Future<List<SyncConflictRow>> all(String userId) =>
      (select(syncConflicts)..where((c) => c.userId.equals(userId))).get();

  Future<SyncConflictRow?> find(
    String userId,
    SyncEntity entity,
    String entityId,
  ) =>
      (select(syncConflicts)..where(
            (c) =>
                c.userId.equals(userId) &
                c.entity.equalsValue(entity) &
                c.entityId.equals(entityId),
          ))
          .getSingleOrNull();

  /// Enregistre le conflit, en remplaçant celui du même enregistrement.
  Future<void> save(SyncConflictsCompanion row) =>
      into(syncConflicts).insertOnConflictUpdate(row);

  Future<void> deleteFor(String userId, SyncEntity entity, String entityId) =>
      (delete(syncConflicts)..where(
            (c) =>
                c.userId.equals(userId) &
                c.entity.equalsValue(entity) &
                c.entityId.equals(entityId),
          ))
          .go();

  Stream<int> watchCount(String userId) {
    final count = syncConflicts.entityId.count();
    return (selectOnly(syncConflicts)
          ..addColumns([count])
          ..where(syncConflicts.userId.equals(userId)))
        .map((row) => row.read(count)!)
        .watchSingle();
  }
}
