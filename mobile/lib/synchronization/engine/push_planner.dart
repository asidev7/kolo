import '../../database/app_database.dart';
import '../wire/sync_dto.dart';

/// Décisions prises **avant** et **après** un envoi, isolées du réseau et de
/// la base pour être testables directement (§3).
///
/// Le moteur ne décide rien lui-même : il applique ce que ces fonctions
/// renvoient.

/// Nombre maximal d'opérations par requête, imposé par l'API.
const int maxOperationsPerPush = 100;

/// Sélectionne le lot à envoyer.
///
/// Deux règles, dans cet ordre :
/// 1. **au plus une opération par enregistrement** : si une même entité a
///    plusieurs entrées dues (création puis modification), seule la plus
///    ancienne part maintenant. L'envoi de la seconde attendrait le résultat
///    de la première pour connaître sa `base_version` — les envoyer ensemble
///    les ferait entrer en conflit entre elles.
/// 2. au plus [max] opérations, dans l'ordre d'écriture.
///
/// [due] doit être triée par `seq` croissant (c'est ce que renvoie
/// `OutboxDao.nextBatch`).
List<OutboxEntry> selectPushBatch(
  List<OutboxEntry> due, {
  int max = maxOperationsPerPush,
}) {
  final batch = <OutboxEntry>[];
  final taken = <String>{};
  for (final entry in due) {
    if (batch.length >= max) break;
    if (!taken.add(entry.entityId)) continue;
    batch.add(entry);
  }
  return batch;
}

/// Version du serveur à adopter par les entrées encore en attente pour un
/// enregistrement qui vient d'être appliqué.
class RebaseTarget {
  const RebaseTarget(this.entityId, this.version);

  final String entityId;
  final int version;
}

/// Cibles de rebasage extraites des résultats de push.
///
/// Sans ce rebasage, l'opération suivante du même enregistrement repartirait
/// avec l'ancienne `base_version` et le serveur la refuserait en conflit alors
/// que le client est à jour.
///
/// `version == 0` (le serveur ne connaissait pas l'enregistrement, par exemple
/// une suppression d'une ligne jamais envoyée) ne rebase rien : il n'y a pas
/// de version à adopter.
List<RebaseTarget> rebaseTargets(List<PushOutcome> outcomes) => [
  for (final outcome in outcomes)
    if (outcome is PushApplied && outcome.version > 0)
      RebaseTarget(outcome.entityId, outcome.version),
];
