import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/technical_tables.dart';

part 'sync_state_dao.g.dart';

@DriftAccessor(tables: [SyncState])
class SyncStateDao extends DatabaseAccessor<AppDatabase>
    with _$SyncStateDaoMixin {
  SyncStateDao(super.attachedDatabase);

  Future<SyncStateRow?> find(String userId) => (select(
    syncState,
  )..where((s) => s.userId.equals(userId))).getSingleOrNull();

  Stream<SyncStateRow?> watch(String userId) => (select(
    syncState,
  )..where((s) => s.userId.equals(userId))).watchSingleOrNull();

  Future<void> save(SyncStateCompanion row) =>
      into(syncState).insertOnConflictUpdate(row);
}
