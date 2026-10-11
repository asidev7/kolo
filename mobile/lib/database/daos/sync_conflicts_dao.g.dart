// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_conflicts_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncConflictsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncConflictsTable get syncConflicts => attachedDatabase.syncConflicts;
  SyncConflictsDaoManager get managers => SyncConflictsDaoManager(this);
}

class SyncConflictsDaoManager {
  final _$SyncConflictsDaoMixin _db;
  SyncConflictsDaoManager(this._db);
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db.attachedDatabase, _db.syncConflicts);
}
