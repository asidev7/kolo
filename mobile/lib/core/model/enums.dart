/// Énumérations partagées entre la base locale, le domaine et la
/// synchronisation. Les noms Dart sont stockés tels quels en base (textEnum) :
/// **ne jamais renommer une valeur** sans migration.
library;

/// Nature d'une opération ou d'une catégorie.
enum TransactionType {
  expense,
  income;

  /// Valeur échangée avec l'API (§4.4).
  String get wire => name;

  static TransactionType fromWire(String value) =>
      TransactionType.values.firstWhere((t) => t.name == value);
}

/// État de synchronisation d'un enregistrement — **côté client uniquement**
/// (§5.2).
enum SyncStatus {
  /// Mode local sans compte : rien à envoyer.
  localOnly,

  /// Modifié localement, en attente d'envoi.
  pending,

  /// Identique à la dernière version confirmée par le serveur.
  synced,

  /// Le serveur a refusé la modification car le même champ a changé des deux
  /// côtés ; l'utilisateur doit trancher.
  conflict,

  /// Rejet définitif (400/403/404) ; affiché, jamais supprimé.
  failed,
}

/// Entités synchronisables.
enum SyncEntity {
  transaction,
  category,
  budget;

  String get wire => name;
}

/// Type d'opération dans l'outbox (§4.3).
enum OutboxOpType {
  upsert,
  delete;

  String get wire => name;
}

/// État d'une entrée d'outbox.
enum OutboxStatus {
  /// À envoyer (éventuellement après `next_attempt_at`).
  pending,

  /// Rejet définitif : conservée pour affichage, n'est plus renvoyée
  /// automatiquement.
  failed,
}
