/// Erreurs métier présentables à l'utilisateur.
///
/// Chaque échec porte un message en français simple, sans jargon technique
/// (§0). Les détails techniques ne sont jamais affichés.
sealed class Failure implements Exception {
  const Failure(this.message);

  /// Message destiné à l'utilisateur.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Saisie invalide, avec les messages par champ.
final class ValidationFailure extends Failure {
  const ValidationFailure(this.fields)
    : super('Vérifie les informations saisies.');

  final Map<String, String> fields;
}

/// Enregistrement introuvable (supprimé entre-temps, par exemple).
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = "Cette opération n'existe plus."]);
}

/// Action interdite dans l'état courant.
final class ForbiddenFailure extends Failure {
  const ForbiddenFailure(super.message);
}

/// Erreur inattendue de stockage local.
final class StorageFailure extends Failure {
  const StorageFailure([
    super.message =
        "L'enregistrement sur le téléphone a échoué. Réessaie dans un instant.",
  ]);
}

/// Erreur renvoyée par l'API, au format `{"error": {code, message, fields}}`.
///
/// `message` vient du serveur : il est écrit en français simple et peut être
/// affiché tel quel (docs/API.md). `code` est stable et destiné au code client
/// (`invalid_credentials`, `duplicate_budget`, …).
final class ApiFailure extends Failure {
  const ApiFailure({
    required this.code,
    required String message,
    this.statusCode,
    this.fields = const {},
  }) : super(message);

  final String code;

  /// `null` si la panne n'a pas produit de réponse HTTP.
  final int? statusCode;

  /// Messages par champ de formulaire, quand l'API en fournit.
  final Map<String, String> fields;
}

/// Panne temporaire : réseau, DNS, délai dépassé, 5xx ou 429.
///
/// L'opération n'a **pas** été refusée : elle doit être réessayée plus tard
/// avec un délai croissant (§6). Rien n'est perdu ni marqué en échec.
final class RetryableFailure extends Failure {
  const RetryableFailure([
    super.message =
        "Le serveur n'est pas joignable. Tes opérations seront envoyées dès "
        'que possible.',
  ]);
}

/// Session expirée et non renouvelable : l'utilisateur doit se reconnecter.
///
/// **L'outbox n'est jamais effacée** dans ce cas (§6) : les opérations en
/// attente repartiront à la prochaine connexion.
final class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure([
    super.message = 'Ta session a expiré. Connecte-toi à nouveau.',
  ]);
}

/// Convertit n'importe quelle erreur en message présentable.
String userMessageFor(Object error) => switch (error) {
  Failure(:final message) => message,
  _ => 'Une erreur inattendue est survenue. Réessaie dans un instant.',
};
