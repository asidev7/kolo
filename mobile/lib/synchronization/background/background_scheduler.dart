import 'package:workmanager/workmanager.dart';

import 'background_sync.dart';

/// Enregistrement de la tâche de fond (§4.6).
///
/// Derrière une interface : les tests n'ont pas de WorkManager, et un substitut
/// en mémoire permet de vérifier *quand* on enregistre ou annule, sans
/// plateforme.
abstract interface class BackgroundSyncScheduler {
  /// Enregistre (ou met à jour) la tâche périodique.
  Future<void> register();

  /// Annule la tâche — appelé à la déconnexion, pour ne pas réveiller
  /// l'application d'un utilisateur qui n'a plus de compte.
  Future<void> cancel();
}

/// Fréquence minimale autorisée par Android pour une tâche périodique.
const Duration backgroundSyncFrequency = Duration(minutes: 15);

class WorkManagerScheduler implements BackgroundSyncScheduler {
  WorkManagerScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  @override
  Future<void> register() async {
    await _workmanager.initialize(koloSyncDispatcher);
    await _workmanager.registerPeriodicTask(
      kSyncTaskName,
      kSyncTaskName,
      frequency: backgroundSyncFrequency,
      // Rien à envoyer sans réseau : attendre évite de réveiller la radio
      // pour rien.
      constraints: Constraints(networkType: NetworkType.connected),
      // `keep` : ne pas réinitialiser le compteur à chaque ouverture de
      // l'application, sinon la tâche ne se déclencherait jamais.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  @override
  Future<void> cancel() => _workmanager.cancelByUniqueName(kSyncTaskName);
}
