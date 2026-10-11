import '../../../core/constants/currencies.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../database/app_database.dart';
import '../../settings/data/settings_keys.dart';
import '../domain/budget.dart';
import 'budget_notifier.dart';
import 'budgets_repository.dart';

/// Alertes de seuil budgétaire (§3.I) : **une seule notification par seuil
/// et par mois**, mémorisée localement. Une dépense reste toujours
/// enregistrable, même en dépassement.
class BudgetAlertService {
  BudgetAlertService({
    required this._db,
    required this._budgets,
    required this._notifier,
  });

  final AppDatabase _db;
  final BudgetsRepository _budgets;
  final LocalNotifier _notifier;

  /// Vérifie le budget de [month] et notifie les seuils nouvellement
  /// franchis. Retourne les seuils notifiés.
  Future<List<int>> check({
    required String? ownerId,
    required YearMonth month,
  }) async {
    if (!await alertsEnabled()) return const [];
    final budget = await _budgets.getEffective(ownerId, month);
    if (budget == null || budget.limitAmount <= 0) return const [];

    final totals = await _db.transactionsDao
        .watchTotals(ownerId, from: month.firstDay, to: month.lastDay)
        .first;
    final status = BudgetStatus.compute(
      limit: budget.limitAmount,
      spent: totals.expense,
      thresholds: budget.alertThresholds,
    );

    final owner = ownerId ?? 'local';
    final already = <int>{};
    for (final t in budget.alertThresholds) {
      if (await _db.settingsDao.read(_key(owner, month, t)) != null) {
        already.add(t);
      }
    }
    final toNotify = thresholdsToNotify(
      percent: status.percent,
      thresholds: budget.alertThresholds,
      alreadyNotified: already,
    );
    if (toNotify.isEmpty) return const [];

    // On mémorise avant d'afficher : en cas d'échec d'affichage, on préfère
    // une alerte manquée à une alerte répétée à chaque saisie.
    for (final t in toNotify) {
      await _db.settingsDao.write(_key(owner, month, t), 'sent');
    }
    // Une seule notification : le seuil le plus élevé franchi.
    final top = toNotify.last;
    final currency = Currencies.of(
      await _db.settingsDao.read(SettingsKeys.currencyCode) ??
          Currencies.defaultCurrency.code,
    );
    await _notifier.show(
      id: month.year * 100 + month.month,
      title: top >= 100
          ? 'Budget du mois dépassé'
          : 'Budget du mois : $top % atteint',
      body: top >= 100
          ? 'Tu as dépensé ${formatMoney(status.spent, currency: currency)} sur '
                '${formatMoney(status.limit, currency: currency)} prévus.'
          : 'Il te reste '
                '${formatMoney(status.remaining, currency: currency)} pour ce mois.',
    );
    return toNotify;
  }

  Future<bool> alertsEnabled() async =>
      await _db.settingsDao.read(SettingsKeys.budgetAlertsEnabled) != 'false';

  Future<void> setAlertsEnabled({required bool enabled}) =>
      _db.settingsDao.write(SettingsKeys.budgetAlertsEnabled, '$enabled');

  String _key(String owner, YearMonth month, int threshold) =>
      '${SettingsKeys.budgetAlertSentPrefix}.$owner.${month.toIso()}.$threshold';
}
