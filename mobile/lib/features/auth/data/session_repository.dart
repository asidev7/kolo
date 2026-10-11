import '../../../core/utils/time_source.dart';
import '../../../database/app_database.dart';
import '../../settings/data/settings_keys.dart';
import '../domain/account.dart';
import '../domain/session.dart';
import 'token_store.dart';

/// Lecture et écriture de la session : préférences dans `app_settings`, jetons
/// dans le coffre sécurisé ([TokenStore]).
///
/// **Aucun jeton ne figure dans `app_settings`** (ARCHITECTURE §5).
class SessionRepository {
  SessionRepository(this._settings, {required this.tokens, required this.ids});

  final SettingsDao _settings;
  final TokenStore tokens;
  final IdGenerator ids;

  Future<Session> load() async {
    final onboardingSeen =
        await _settings.read(SettingsKeys.onboardingSeen) == 'true';
    final mode = switch (await _settings.read(SettingsKeys.sessionMode)) {
      'local' => SessionMode.local,
      'account' => SessionMode.account,
      _ => SessionMode.none,
    };
    return Session(
      onboardingSeen: onboardingSeen,
      mode: mode,
      userId: await _settings.read(SettingsKeys.accountUserId),
      displayName: await _settings.read(SettingsKeys.accountDisplayName),
      email: await _settings.read(SettingsKeys.accountEmail),
    );
  }

  Future<void> markOnboardingSeen() =>
      _settings.write(SettingsKeys.onboardingSeen, 'true');

  Future<void> startLocalMode() =>
      _settings.write(SettingsKeys.sessionMode, 'local');

  /// Enregistre la connexion : jetons au coffre, identité dans les
  /// préférences. Le mode passe à `account`, ce qui fait basculer le routeur.
  Future<void> signIn(AccountSession session) async {
    await tokens.write(session.tokens);
    await _settings.write(SettingsKeys.sessionMode, 'account');
    await _saveIdentity(session.account);
  }

  /// Met à jour le prénom / l'e-mail affichés après un `PATCH /auth/me`.
  Future<void> updateAccount(Account account) => _saveIdentity(account);

  /// Déconnexion (D34) : le mode repasse à `none`, l'écran d'accueil
  /// réapparaît. **Les données locales restent** : celles du compte
  /// (`user_id = <compte>`) et celles du profil local (`user_id IS NULL`),
  /// retrouvées en repassant en mode local.
  Future<void> signOut() async {
    await tokens.clear();
    await _settings.remove(SettingsKeys.sessionMode);
    await _settings.remove(SettingsKeys.accountUserId);
    await _settings.remove(SettingsKeys.accountDisplayName);
    await _settings.remove(SettingsKeys.accountEmail);
  }

  /// Identifiant de cette installation, envoyé comme `device_id` au serveur.
  /// Généré une fois puis conservé : il ne change pas d'une session à l'autre.
  Future<String> deviceId() async {
    final existing = await _settings.read(SettingsKeys.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = ids();
    await _settings.write(SettingsKeys.deviceId, generated);
    return generated;
  }

  Future<void> _saveIdentity(Account account) async {
    await _settings.write(SettingsKeys.accountUserId, account.id);
    await _settings.write(SettingsKeys.accountDisplayName, account.firstName);
    await _settings.write(SettingsKeys.accountEmail, account.email);
  }
}
