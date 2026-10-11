import 'dart:convert';

import '../../../core/constants/currencies.dart';
import '../../../core/errors/failures.dart';
import '../../../core/model/enums.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/time_source.dart';
import '../../../database/app_database.dart';
import '../../../synchronization/outbox/outbox_planner.dart';
import '../../../synchronization/outbox/outbox_writer.dart';
import '../../../synchronization/wire/payloads.dart';
import '../../settings/data/settings_keys.dart';
import '../domain/budget.dart';

Budget budgetFromRow(BudgetRow row) => Budget(
  id: row.id,
  period: YearMonth.parse(row.period),
  limitAmount: row.limitAmount,
  alertThresholds: (jsonDecode(row.alertThresholds) as List<Object?>)
      .whereType<int>()
      .toList(),
);

class BudgetsRepository {
  BudgetsRepository({
    required this._db,
    required this._writer,
    required this._time,
    required this._ids,
    void Function()? onLocalWrite,
  }) : _onLocalWrite = onLocalWrite ?? _noop;

  final AppDatabase _db;
  final OutboxWriter _writer;
  final TimeSource _time;
  final IdGenerator _ids;
  final void Function() _onLocalWrite;

  static void _noop() {}

  /// Budget applicable au mois (reconduction comprise).
  Stream<Budget?> watchEffective(String? ownerId, YearMonth month) => _db
      .budgetsDao
      .watchEffective(ownerId, month)
      .map((row) => row == null ? null : budgetFromRow(row));

  Future<Budget?> getEffective(String? ownerId, YearMonth month) async {
    final row = await _db.budgetsDao.getEffective(ownerId, month);
    return row == null ? null : budgetFromRow(row);
  }

  /// Fixe le plafond à partir de [month]. Les mois précédents gardent leur
  /// budget ; les mois suivants en héritent tant qu'ils n'en ont pas.
  Future<void> setMonthlyLimit({
    required String? ownerId,
    required YearMonth month,
    required int limitAmount,
    List<int> thresholds = Budget.defaultThresholds,
  }) async {
    final currency = Currencies.of(
      await _db.settingsDao.read(SettingsKeys.currencyCode) ??
          Currencies.defaultCurrency.code,
    );
    if (limitAmount < 0 || limitAmount > kMaxAmount) {
      throw ValidationFailure({
        'limit': 'Saisis un plafond entre 0 et '
            '${formatMoney(kMaxAmount, currency: currency)}.',
      });
    }
    final cleanThresholds =
        thresholds.where((t) => t > 0 && t <= 200).toSet().toList()..sort();

    await _writer.transaction((outbox) async {
      final now = _time.nowUtc();
      final status = ownerId == null
          ? SyncStatus.localOnly
          : SyncStatus.pending;
      final existing = await _db.budgetsDao.findForPeriod(ownerId, month);
      final BudgetRow row;
      final Set<String> changed;
      if (existing == null) {
        row = BudgetRow(
          id: _ids(),
          userId: ownerId,
          period: month.toIso(),
          limitAmount: limitAmount,
          currency: currency.code,
          alertThresholds: jsonEncode(cleanThresholds),
          createdAt: now,
          updatedAt: now,
          version: 0,
          syncStatus: status,
        );
        await _db.into(_db.budgets).insert(row);
        changed = Payloads.budget(row).keys.toSet();
      } else {
        row = existing.copyWith(
          limitAmount: limitAmount,
          alertThresholds: jsonEncode(cleanThresholds),
          updatedAt: now,
          syncStatus: status,
        );
        changed = diffFields(Payloads.budget(existing), Payloads.budget(row));
        if (changed.isEmpty) return;
        await _db.update(_db.budgets).replace(row);
      }
      if (ownerId != null) {
        await outbox.record(
          OutboxRequest(
            entity: SyncEntity.budget,
            entityId: row.id,
            opType: OutboxOpType.upsert,
            payload: Payloads.budget(row),
            changedFields: changed,
            baseVersion: existing?.version ?? 0,
            userId: ownerId,
          ),
        );
      }
    });
    _onLocalWrite();
  }
}
