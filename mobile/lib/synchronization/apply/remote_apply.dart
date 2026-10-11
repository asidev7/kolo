import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/errors/failures.dart';
import '../../core/model/enums.dart';
import '../../core/network/json_reader.dart';
import '../../core/utils/text_normalize.dart';
import '../../core/utils/time_source.dart';
import '../../database/app_database.dart';
import '../wire/sync_dto.dart';

/// **Seul** endroit qui écrit des enregistrements venus du serveur (§5).
///
/// Les dépôts métier, eux, écrivent toujours l'enregistrement *et* son entrée
/// d'outbox dans une même transaction. Ici c'est l'inverse : l'enregistrement
/// arrive déjà validé par le serveur, il n'y a donc **jamais** d'entrée
/// d'outbox à écrire. Mélanger les deux chemins ferait renvoyer au serveur ce
/// qu'il vient de nous envoyer.
class RemoteApplier {
  RemoteApplier(this._db, this._time);

  final AppDatabase _db;
  final TimeSource _time;

  // -------------------------------------------------------------------------
  // Résultats d'un push (§3)
  // -------------------------------------------------------------------------

  /// Applique les résultats d'un envoi, dans une seule transaction.
  ///
  /// Le type d'opération (`upsert`/`delete`) n'est pas répété par le serveur,
  /// mais il n'est pas nécessaire : `deleted_at` renvoyé dit à lui seul si
  /// l'enregistrement est vivant ou supprimé, et l'entrée d'outbox est
  /// retrouvée par `op_id` (clé d'idempotence unique).
  Future<PushApplyReport> applyPushResults({
    required String userId,
    required List<PushOutcome> outcomes,
  }) async {
    var requiresFullPull = false;

    await _db.transaction(() async {
      for (final outcome in outcomes) {
        switch (outcome) {
          case PushApplied():
            await _db.outboxDao.removeByOpIds([outcome.opId]);
            await _acceptServerVersion(outcome);
          case PushConflict():
            await _storeConflict(userId, outcome);
          case PushRejected():
            if (outcome.code == _duplicateBudget) {
              // D33 : le serveur détient un budget de même `(période, catégorie)`
              // sous un autre identifiant. Le budget local n'a jamais existé
              // côté serveur : on le supprime franchement (pas de tombstone,
              // qui créerait une ligne fantôme) et on repart d'un pull complet.
              await _db.outboxDao.deleteAllFor(outcome.entityId);
              await _deleteBudgetRow(outcome.entityId);
              requiresFullPull = true;
            } else {
              await _markRejected(outcome);
            }
        }
      }
    });

    return PushApplyReport(requiresFullPull: requiresFullPull);
  }

  /// Le serveur a accepté l'opération : on adopte sa version.
  ///
  /// L'enregistrement cesse d'être `pending` **sauf** s'il reste une autre
  /// entrée d'outbox pour lui (une modification faite pendant l'aller-retour).
  Future<void> _acceptServerVersion(PushApplied outcome) async {
    final status = await _db.outboxDao.pendingCountFor(outcome.entityId) > 0
        ? SyncStatus.pending
        : SyncStatus.synced;

    // `deleted_at` est écrit tel quel : renseigné, il confirme un tombstone ;
    // nul, il peut aussi bien signifier « enregistrement vivant » que
    // « restauration explicite d'un enregistrement supprimé ».
    final deletedAt = outcome.deletedAt;

    switch (outcome.entity) {
      case SyncEntity.transaction:
        final existing = await _db.transactionsDao.findById(outcome.entityId);
        if (existing == null) return;
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(outcome.entityId))).write(
          TransactionsCompanion(
            version: Value(outcome.version),
            serverUpdatedAt: Value(
              outcome.serverUpdatedAt ?? existing.serverUpdatedAt,
            ),
            deletedAt: Value(deletedAt),
            syncStatus: Value(status),
          ),
        );
      case SyncEntity.category:
        final existing = await _db.categoriesDao.findById(outcome.entityId);
        if (existing == null) return;
        await (_db.update(
          _db.categories,
        )..where((c) => c.id.equals(outcome.entityId))).write(
          CategoriesCompanion(
            version: Value(outcome.version),
            serverUpdatedAt: Value(
              outcome.serverUpdatedAt ?? existing.serverUpdatedAt,
            ),
            deletedAt: Value(deletedAt),
            syncStatus: Value(status),
          ),
        );
      case SyncEntity.budget:
        final existing = await _db.budgetsDao.findById(outcome.entityId);
        if (existing == null) return;
        await (_db.update(
          _db.budgets,
        )..where((b) => b.id.equals(outcome.entityId))).write(
          BudgetsCompanion(
            version: Value(outcome.version),
            serverUpdatedAt: Value(
              outcome.serverUpdatedAt ?? existing.serverUpdatedAt,
            ),
            deletedAt: Value(deletedAt),
            syncStatus: Value(status),
          ),
        );
    }
  }

  /// Le même champ a changé des deux côtés : les deux versions sont conservées
  /// et l'utilisateur tranche (§5). La version locale reste intacte.
  Future<void> _storeConflict(String userId, PushConflict outcome) async {
    final server = outcome.serverRecord;
    await _db.outboxDao.removeByOpIds([outcome.opId]);
    await _db.syncConflictsDao.save(
      SyncConflictsCompanion.insert(
        userId: userId,
        entity: outcome.entity,
        entityId: outcome.entityId,
        reason: outcome.reason,
        serverVersion: server.version,
        serverUpdatedAt: Value(server.serverUpdatedAt),
        serverData: jsonEncode(server.data),
        conflictingFields: Value(jsonEncode(outcome.conflictingFields)),
        createdAt: _time.nowUtc(),
      ),
    );
    await _setStatus(outcome.entity, outcome.entityId, SyncStatus.conflict);
  }

  /// Refus définitif : l'entrée d'outbox et l'enregistrement sont marqués en
  /// échec. Rien n'est supprimé — l'utilisateur doit voir ce qui a été refusé.
  Future<void> _markRejected(PushRejected outcome) async {
    await _db.outboxDao.markFailedByOpId(outcome.opId, outcome.code);
    final status = await _db.outboxDao.pendingCountFor(outcome.entityId) > 0
        ? SyncStatus.pending
        : SyncStatus.failed;
    await _setStatus(outcome.entity, outcome.entityId, status);
  }

  Future<void> _setStatus(
    SyncEntity entity,
    String entityId,
    SyncStatus status,
  ) async {
    switch (entity) {
      case SyncEntity.transaction:
        await (_db.update(_db.transactions)
              ..where((t) => t.id.equals(entityId)))
            .write(TransactionsCompanion(syncStatus: Value(status)));
      case SyncEntity.category:
        await (_db.update(_db.categories)..where((c) => c.id.equals(entityId)))
            .write(CategoriesCompanion(syncStatus: Value(status)));
      case SyncEntity.budget:
        await (_db.update(_db.budgets)..where((b) => b.id.equals(entityId)))
            .write(BudgetsCompanion(syncStatus: Value(status)));
    }
  }

  Future<void> _deleteBudgetRow(String budgetId) =>
      (_db.delete(_db.budgets)..where((b) => b.id.equals(budgetId))).go();

  // -------------------------------------------------------------------------
  // Pull (§3)
  // -------------------------------------------------------------------------

  /// Applique une page de changements et enregistre le curseur.
  ///
  /// Les enregistrements ayant une modification locale non envoyée sont
  /// **ignorés** : sans cela, un aller-retour de réseau écraserait la saisie de
  /// l'utilisateur par une version plus ancienne.
  Future<void> applyPull({
    required String userId,
    required List<ServerRecord> records,
    required String nextCursor,
    DateTime? serverTime,
  }) async {
    // Le serveur ordonne déjà catégories → budgets → opérations ; on le refait
    // pour que la clé étrangère des opérations soit toujours satisfaite, même
    // si une page arrive dans un autre ordre.
    final ordered = [...records]
      ..sort((a, b) => _entityRank(a.entity).compareTo(_entityRank(b.entity)));

    await _db.transaction(() async {
      for (final record in ordered) {
        if (await _hasLocalPriority(record.entity, record.entityId)) continue;
        await _applyRecord(userId, record);
      }
      await _db.syncStateDao.save(
        SyncStateCompanion(
          userId: Value(userId),
          cursor: Value(nextCursor),
          lastSuccessAt: Value(serverTime ?? _time.nowUtc()),
          lastAttemptAt: Value(_time.nowUtc()),
          lastError: const Value(null),
        ),
      );
    });
  }

  static int _entityRank(SyncEntity entity) => switch (entity) {
    SyncEntity.category => 0,
    SyncEntity.budget => 1,
    SyncEntity.transaction => 2,
  };

  /// Une modification locale non envoyée, ou un conflit en attente de choix,
  /// l'emporte sur la version du serveur.
  Future<bool> _hasLocalPriority(SyncEntity entity, String entityId) async {
    if (await _db.outboxDao.hasPendingFor(entityId)) return true;
    return await _localStatus(entity, entityId) == SyncStatus.conflict;
  }

  Future<SyncStatus?> _localStatus(SyncEntity entity, String entityId) async {
    final status = switch (entity) {
      SyncEntity.transaction => (await _db.transactionsDao.findById(
        entityId,
      ))?.syncStatus,
      SyncEntity.category => (await _db.categoriesDao.findById(
        entityId,
      ))?.syncStatus,
      SyncEntity.budget => (await _db.budgetsDao.findById(
        entityId,
      ))?.syncStatus,
    };
    return status;
  }

  Future<void> _applyRecord(String userId, ServerRecord record) async {
    switch (record.entity) {
      case SyncEntity.transaction:
        await _applyTransaction(userId, record);
      case SyncEntity.category:
        await _applyCategory(userId, record);
      case SyncEntity.budget:
        await _applyBudget(userId, record);
    }
  }

  Future<void> _applyTransaction(String userId, ServerRecord record) async {
    final existing = await _db.transactionsDao.findById(record.entityId);
    // Un tombstone sur un enregistrement que ce téléphone n'a jamais vu
    // n'apprend rien : l'absence est déjà l'état voulu, et créer la ligne
    // ferait échouer la clé étrangère si la catégorie a été purgée.
    if (record.isDeleted && existing == null) return;

    final data = record.data;
    final note = data.optionalString('note');
    final serverUpdatedAt = record.serverUpdatedAt ?? _time.nowUtc();
    await _db
        .into(_db.transactions)
        .insertOnConflictUpdate(
          TransactionsCompanion(
            id: Value(record.entityId),
            userId: Value(userId),
            type: Value(_transactionType(data.requireString('type'))),
            amount: Value(data.requireInt('amount')),
            currency: Value(data.optionalString('currency') ?? 'XOF'),
            categoryId: Value(data.requireString('category_id')),
            note: Value(note),
            noteSearch: Value(note == null ? null : normalizeForSearch(note)),
            occurredOn: Value(data.requireString('occurred_on')),
            createdAt: Value(existing?.createdAt ?? serverUpdatedAt),
            updatedAt: Value(serverUpdatedAt),
            version: Value(record.version),
            serverUpdatedAt: Value(record.serverUpdatedAt),
            deletedAt: Value(record.deletedAt),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  }

  Future<void> _applyCategory(String userId, ServerRecord record) async {
    final existing = await _db.categoriesDao.findById(record.entityId);
    if (record.isDeleted && existing == null) return;

    final data = record.data;
    final serverUpdatedAt = record.serverUpdatedAt ?? _time.nowUtc();
    await _db
        .into(_db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion(
            id: Value(record.entityId),
            userId: Value(userId),
            name: Value(data.requireString('name')),
            type: Value(_transactionType(data.requireString('type'))),
            icon: Value(data.requireString('icon')),
            color: Value(data.optionalString('color')),
            // Les catégories par défaut ne transitent jamais : celles qui
            // arrivent d'ici appartiennent au compte.
            isDefault: const Value(false),
            sortOrder: Value(data.optionalInt('sort_order') ?? 0),
            createdAt: Value(existing?.createdAt ?? serverUpdatedAt),
            updatedAt: Value(serverUpdatedAt),
            version: Value(record.version),
            serverUpdatedAt: Value(record.serverUpdatedAt),
            deletedAt: Value(record.deletedAt),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  }

  Future<void> _applyBudget(String userId, ServerRecord record) async {
    final existing = await _db.budgetsDao.findById(record.entityId);
    if (record.isDeleted && existing == null) return;

    if (!record.isDeleted) {
      // Le serveur fait autorité sur `(compte, période, catégorie)` : si ce
      // téléphone a créé le même mois sous un autre identifiant, la ligne
      // locale cède la place (sinon l'index unique refuserait l'insertion).
      final collision = await _db.budgetsDao.findColliding(
        userId,
        record.data.requireString('period'),
        record.data.optionalString('category_id'),
        excludingId: record.entityId,
      );
      if (collision != null) {
        await _db.outboxDao.deleteAllFor(collision.id);
        await _deleteBudgetRow(collision.id);
      }
    }

    final data = record.data;
    final serverUpdatedAt = record.serverUpdatedAt ?? _time.nowUtc();
    await _db
        .into(_db.budgets)
        .insertOnConflictUpdate(
          BudgetsCompanion(
            id: Value(record.entityId),
            userId: Value(userId),
            period: Value(data.requireString('period')),
            categoryId: Value(data.optionalString('category_id')),
            limitAmount: Value(data.requireInt('limit_amount')),
            currency: Value(data.optionalString('currency') ?? 'XOF'),
            alertThresholds: Value(
              jsonEncode(
                data['alert_thresholds'] is List<Object?>
                    ? (data['alert_thresholds']! as List<Object?>)
                          .whereType<int>()
                          .toList(growable: false)
                    : const [80, 100],
              ),
            ),
            createdAt: Value(existing?.createdAt ?? serverUpdatedAt),
            updatedAt: Value(serverUpdatedAt),
            version: Value(record.version),
            serverUpdatedAt: Value(record.serverUpdatedAt),
            deletedAt: Value(record.deletedAt),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  }

  // -------------------------------------------------------------------------
  // Purge après un pull complet (§3, cas `410`)
  // -------------------------------------------------------------------------

  /// Supprime les enregistrements `synced` du compte absents du pull complet.
  ///
  /// Uniquement des lignes confirmées par le serveur : tout ce qui est
  /// `pending`, `conflict`, `failed` ou `localOnly` est conservé — une purge ne
  /// doit jamais faire disparaître une saisie de l'utilisateur.
  ///
  /// Ordre imposé par les clés étrangères : opérations, puis budgets, puis
  /// catégories.
  Future<int> purgeSyncedNotSeen({
    required String userId,
    required Set<String> seenIds,
  }) async {
    var removed = 0;
    await _db.transaction(() async {
      final transactionRows =
          await (_db.select(_db.transactions)..where(
                (t) =>
                    t.userId.equals(userId) &
                    t.syncStatus.equalsValue(SyncStatus.synced),
              ))
              .get();
      final staleTransactions = [
        for (final row in transactionRows)
          if (!seenIds.contains(row.id)) row.id,
      ];
      if (staleTransactions.isNotEmpty) {
        removed += await (_db.delete(
          _db.transactions,
        )..where((t) => t.id.isIn(staleTransactions))).go();
      }

      final budgetRows =
          await (_db.select(_db.budgets)..where(
                (b) =>
                    b.userId.equals(userId) &
                    b.syncStatus.equalsValue(SyncStatus.synced),
              ))
              .get();
      final staleBudgets = [
        for (final row in budgetRows)
          if (!seenIds.contains(row.id)) row.id,
      ];
      if (staleBudgets.isNotEmpty) {
        removed += await (_db.delete(
          _db.budgets,
        )..where((b) => b.id.isIn(staleBudgets))).go();
      }

      final categoryRows =
          await (_db.select(_db.categories)..where(
                (c) =>
                    c.userId.equals(userId) &
                    c.syncStatus.equalsValue(SyncStatus.synced) &
                    c.isDefault.equals(false),
              ))
              .get();
      final staleCategories = [
        for (final row in categoryRows)
          if (!seenIds.contains(row.id)) row.id,
      ];
      if (staleCategories.isNotEmpty) {
        removed += await (_db.delete(
          _db.categories,
        )..where((c) => c.id.isIn(staleCategories))).go();
      }
    });
    return removed;
  }

  TransactionType _transactionType(String value) {
    for (final type in TransactionType.values) {
      if (type.wire == value) return type;
    }
    throw ApiFailure(
      code: 'invalid_response',
      message: 'Réponse inattendue du serveur.',
      fields: {'type': value},
    );
  }
}

/// Ce qu'un lot de résultats de push a changé pour la suite du cycle.
class PushApplyReport {
  const PushApplyReport({this.requiresFullPull = false});

  /// Le curseur doit repartir de 0 : le serveur détient un enregistrement que
  /// le client ne connaît pas (rejet `duplicate_budget`, D33).
  final bool requiresFullPull;
}

const String _duplicateBudget = 'duplicate_budget';
