import 'package:drift/drift.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/errors/failures.dart';
import '../../../core/model/enums.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/text_normalize.dart';
import '../../../core/utils/time_source.dart';
import '../../../database/app_database.dart';
import '../../../synchronization/outbox/outbox_planner.dart';
import '../../../synchronization/outbox/outbox_writer.dart';
import '../../../synchronization/wire/payloads.dart';
import '../../categories/data/categories_repository.dart';
import '../../settings/data/settings_keys.dart';
import '../domain/transaction.dart';
import '../domain/transaction_validator.dart';

KoloTransaction transactionFromRow(TransactionRow row) => KoloTransaction(
  id: row.id,
  userId: row.userId,
  type: row.type,
  amount: row.amount,
  currency: row.currency,
  categoryId: row.categoryId,
  note: row.note,
  occurredOn: LocalDate.parse(row.occurredOn),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  version: row.version,
  syncStatus: row.syncStatus,
  deletedAt: row.deletedAt,
);

/// Résultat d'un enregistrement.
enum SaveOutcome { created, updated, unchanged }

/// Écritures et lectures des opérations (§4.2).
///
/// Toute écriture : validation domaine → **une** transaction SQLite qui
/// modifie l'opération et journalise l'outbox → notification [onLocalWrite]
/// (déclenche une synchronisation non bloquante).
class TransactionsRepository {
  TransactionsRepository({
    required this._db,
    required this._writer,
    required this._time,
    void Function()? onLocalWrite,
  }) : _onLocalWrite = onLocalWrite ?? _noop;

  final AppDatabase _db;
  final OutboxWriter _writer;
  final TimeSource _time;
  final void Function() _onLocalWrite;

  static void _noop() {}

  Stream<List<KoloTransaction>> watchRecent(String? ownerId, {int limit = 5}) =>
      _db.transactionsDao
          .watchRecent(ownerId, limit: limit)
          .map((rows) => rows.map(transactionFromRow).toList());

  Stream<KoloTransaction?> watchById(String id) => _db.transactionsDao
      .watchById(id)
      .map((row) => row == null ? null : transactionFromRow(row));

  /// Catégorie à présélectionner dans le formulaire (§3.E).
  Future<String?> lastUsedCategoryId(String? ownerId, TransactionType type) =>
      _db.transactionsDao.lastUsedCategoryId(ownerId, type);

  Future<KoloTransaction?> findById(String id) async {
    final row = await _db.transactionsDao.findById(id);
    return row == null ? null : transactionFromRow(row);
  }

  /// Crée ou modifie l'opération [id].
  ///
  /// L'identifiant est généré **à l'ouverture du formulaire** : une double
  /// soumission retrouve l'opération déjà créée, au contenu identique, et ne
  /// produit aucun doublon ([SaveOutcome.unchanged]).
  Future<SaveOutcome> save({
    required String id,
    required String? ownerId,
    required TransactionDraft draft,
  }) async {
    final currencyCode =
        await _db.settingsDao.read(SettingsKeys.currencyCode) ??
        Currencies.defaultCurrency.code;
    final currency = Currencies.of(currencyCode);
    final outcome = await _writer.transaction((outbox) async {
      final existing = await _db.transactionsDao.findById(id);
      if (existing != null && existing.userId != ownerId) {
        throw const ForbiddenFailure("Cette opération n'est pas accessible.");
      }
      if (existing?.deletedAt != null) throw const NotFoundFailure();

      final categoryRow = draft.categoryId == null
          ? null
          : await _db.categoriesDao.findById(draft.categoryId!);
      final category = categoryRow == null || !_visible(categoryRow, ownerId)
          ? null
          : categoryFromRow(categoryRow);
      final errors = TransactionValidator.validate(
        draft,
        today: _time.today(),
        category: category,
        allowArchivedCategory: existing?.categoryId == draft.categoryId,
        currency: currency,
      );
      if (errors.isNotEmpty) throw ValidationFailure(errors);

      final note = draft.normalizedNote;
      final now = _time.nowUtc();
      final status = ownerId == null
          ? SyncStatus.localOnly
          : SyncStatus.pending;

      if (existing == null) {
        final row = TransactionRow(
          id: id,
          userId: ownerId,
          type: draft.type,
          amount: draft.amount!,
          currency: currencyCode,
          categoryId: draft.categoryId!,
          note: note,
          noteSearch: note == null ? null : normalizeForSearch(note),
          occurredOn: draft.occurredOn.toIso(),
          createdAt: now,
          updatedAt: now,
          version: 0,
          syncStatus: status,
        );
        await _db.into(_db.transactions).insert(row);
        if (ownerId != null) {
          final payload = Payloads.transaction(row);
          await outbox.record(
            _request(
              id,
              ownerId,
              OutboxOpType.upsert,
              payload,
              payload.keys.toSet(),
              0,
            ),
          );
        }
        return SaveOutcome.created;
      }

      final updated = existing.copyWith(
        type: draft.type,
        amount: draft.amount,
        categoryId: draft.categoryId,
        note: Value(note),
        noteSearch: Value(note == null ? null : normalizeForSearch(note)),
        occurredOn: draft.occurredOn.toIso(),
      );
      final before = Payloads.transaction(existing);
      final after = Payloads.transaction(updated);
      final changed = diffFields(before, after);
      if (changed.isEmpty) return SaveOutcome.unchanged;

      await _db
          .update(_db.transactions)
          .replace(updated.copyWith(updatedAt: now, syncStatus: status));
      if (ownerId != null) {
        await outbox.record(
          _request(
            id,
            ownerId,
            OutboxOpType.upsert,
            after,
            changed,
            existing.version,
          ),
        );
      }
      return SaveOutcome.updated;
    });
    if (outcome != SaveOutcome.unchanged) _onLocalWrite();
    return outcome;
  }

  /// Suppression logique (tombstone, §4.2). Sans effet si l'opération est
  /// déjà supprimée.
  Future<void> delete({required String id, required String? ownerId}) async {
    final deleted = await _writer.transaction((outbox) async {
      final existing = await _db.transactionsDao.findById(id);
      if (existing == null || existing.deletedAt != null) return false;
      if (existing.userId != ownerId) {
        throw const ForbiddenFailure("Cette opération n'est pas accessible.");
      }
      final now = _time.nowUtc();
      await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: Value(
            ownerId == null ? SyncStatus.localOnly : SyncStatus.pending,
          ),
        ),
      );
      if (ownerId != null) {
        await outbox.record(
          _request(
            id,
            ownerId,
            OutboxOpType.delete,
            const {},
            const {},
            existing.version,
          ),
        );
      }
      return true;
    });
    if (deleted) _onLocalWrite();
  }

  bool _visible(CategoryRow row, String? ownerId) =>
      row.isDefault || row.userId == ownerId;

  OutboxRequest _request(
    String id,
    String ownerId,
    OutboxOpType opType,
    Map<String, Object?> payload,
    Set<String> changed,
    int baseVersion,
  ) => OutboxRequest(
    entity: SyncEntity.transaction,
    entityId: id,
    opType: opType,
    payload: payload,
    changedFields: changed,
    baseVersion: baseVersion,
    userId: ownerId,
  );
}
