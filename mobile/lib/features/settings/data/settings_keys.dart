/// Clés de la table `app_settings`. Centralisées pour éviter les fautes de
/// frappe : **ne jamais renommer une clé existante** (les valeurs déjà
/// enregistrées seraient perdues).
abstract final class SettingsKeys {
  static const onboardingSeen = 'onboarding.seen';

  /// `local` ou `account` ; absent tant que l'utilisateur n'a pas choisi.
  static const sessionMode = 'session.mode';
  static const accountUserId = 'account.user_id';
  static const accountDisplayName = 'account.display_name';
  static const accountEmail = 'account.email';

  /// Identifiant de cette installation (`device_id` de `sync/push`).
  static const deviceId = 'device.id';

  static const budgetAlertsEnabled = 'budget.alerts_enabled';

  /// Devise choisie (code ISO 4217). Absente tant que l'utilisateur n'a rien
  /// choisi : l'application reste en XOF.
  static const currencyCode = 'prefs.currency';

  /// Préfixe des seuils déjà notifiés : `budget.alert_sent.<owner>.<YYYY-MM>.<seuil>`.
  static const budgetAlertSentPrefix = 'budget.alert_sent';
}
