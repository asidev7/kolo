/// État affiché par le badge de synchronisation (§3.D).
///
/// Modèle pur, sans dépendance à Flutter : `core/widgets/sync_status_badge.dart`
/// ne fait que le dessiner, et [syncBadgeState] se teste sans widget.
sealed class SyncBadgeState {
  const SyncBadgeState();
}

/// Mode local : rien n'est envoyé, et on le dit clairement.
final class SyncBadgeLocal extends SyncBadgeState {
  const SyncBadgeLocal();
}

final class SyncBadgeSynced extends SyncBadgeState {
  const SyncBadgeSynced();
}

final class SyncBadgePending extends SyncBadgeState {
  const SyncBadgePending(this.count);

  final int count;
}

final class SyncBadgeOffline extends SyncBadgeState {
  const SyncBadgeOffline(this.pendingCount);

  final int pendingCount;
}

final class SyncBadgeError extends SyncBadgeState {
  const SyncBadgeError();
}

final class SyncBadgeInProgress extends SyncBadgeState {
  const SyncBadgeInProgress();
}

/// Compte connecté, rien en attente, mais le serveur n'a encore jamais
/// confirmé : afficher « Synchronisé » serait un mensonge.
final class SyncBadgeWaiting extends SyncBadgeState {
  const SyncBadgeWaiting();
}

/// Résumé affiché en haut du tableau de bord.
///
/// Fonction pure : la même combinaison produit toujours le même badge, ce qui
/// permet de la tester exhaustivement.
SyncBadgeState syncBadgeState({
  required bool isAccount,
  required bool offline,
  required bool running,
  required bool hasError,
  required bool hasSyncedOnce,
  required int pendingCount,
}) {
  if (!isAccount) return const SyncBadgeLocal();
  // Un cycle en cours prime sur tout le reste : c'est l'information du moment.
  if (running) return const SyncBadgeInProgress();
  // Une erreur reste affichée jusqu'à la prochaine réussite.
  if (hasError) return const SyncBadgeError();
  if (pendingCount > 0) {
    return offline
        ? SyncBadgeOffline(pendingCount)
        : SyncBadgePending(pendingCount);
  }
  if (hasSyncedOnce) return const SyncBadgeSynced();
  return offline ? const SyncBadgeOffline(0) : const SyncBadgeWaiting();
}
