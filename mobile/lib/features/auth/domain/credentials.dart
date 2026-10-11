/// Contrôles **locaux** des identifiants, avant tout appel réseau.
///
/// Ils évitent un aller-retour inutile pour une faute évidente ; le serveur
/// reste l'autorité (il refuse aussi les mots de passe trop courants ou trop
/// proches de l'adresse — docs/API.md).
///
/// Chaque fonction renvoie `null` si la valeur est acceptable, sinon le
/// message à afficher sous le champ.
library;

/// Clés de champ utilisées par l'API : `ApiFailure.fields` arrive avec ces
/// mêmes noms, les erreurs locales et distantes s'affichent donc au même
/// endroit.
const firstNameField = 'first_name';
const emailField = 'email';
const passwordField = 'password';
const codeField = 'code';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Suffisamment courts pour être mémorisables, assez longs pour ne pas être
/// devinés en quelques essais.
const minPasswordLength = 8;

String? validateFirstName(String value) =>
    value.trim().isEmpty ? 'Indique ton prénom.' : null;

String? validateEmail(String value) =>
    _emailPattern.hasMatch(value.trim()) ? null : 'Adresse e-mail invalide.';

String? validatePassword(String value, {String? email, String? firstName}) {
  if (value.length < minPasswordLength) {
    return 'Au moins $minPasswordLength caractères.';
  }
  if (int.tryParse(value) != null) {
    return 'Un mot de passe entièrement numérique est trop facile à deviner.';
  }
  final lowered = value.toLowerCase();
  final localPart = email?.split('@').first.trim().toLowerCase();
  if (localPart != null &&
      localPart.isNotEmpty &&
      lowered.contains(localPart)) {
    return 'Évite d’y mettre ton adresse e-mail.';
  }
  final name = firstName?.trim().toLowerCase();
  if (name != null && name.length >= 3 && lowered.contains(name)) {
    return 'Évite d’y mettre ton prénom.';
  }
  return null;
}

/// Code de réinitialisation : 6 chiffres (docs/API.md).
String? validateResetCode(String value) =>
    RegExp(r'^\d{6}$').hasMatch(value.trim())
    ? null
    : 'Le code fait 6 chiffres.';
