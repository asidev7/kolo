import 'package:meta/meta.dart';

import '../../core/model/enums.dart';

/// Opération à journaliser, telle que produite par un repository.
@immutable
class OutboxRequest {
  const OutboxRequest({
    required this.entity,
    required this.entityId,
    required this.opType,
    required this.payload,
    required this.changedFields,
    required this.baseVersion,
    required this.userId,
  });

  final SyncEntity entity;
  final String entityId;
  final OutboxOpType opType;
  final Map<String, Object?> payload;
  final Set<String> changedFields;

  /// Version serveur connue au moment de la modification (0 = création).
  final int baseVersion;
  final String userId;
}

/// Ce qui est déjà en attente pour le même enregistrement.
@immutable
class PendingOutboxEntry {
  const PendingOutboxEntry({
    required this.seq,
    required this.opType,
    required this.baseVersion,
    required this.attempts,
    required this.changedFields,
  });

  final int seq;
  final OutboxOpType opType;
  final int baseVersion;
  final int attempts;
  final Set<String> changedFields;
}

/// Décision d'écriture dans l'outbox.
sealed class OutboxPlan {
  const OutboxPlan();
}

/// Ajouter une nouvelle entrée.
final class AppendEntry extends OutboxPlan {
  const AppendEntry(this.request);

  final OutboxRequest request;
}

/// Remplacer l'entrée [seq] (jamais envoyée) par une entrée fusionnée.
final class ReplaceEntry extends OutboxPlan {
  const ReplaceEntry(this.seq, this.request);

  final int seq;
  final OutboxRequest request;
}

/// Supprimer l'entrée [seq] sans rien ajouter : l'enregistrement, créé puis
/// supprimé avant tout envoi, n'a jamais existé côté serveur.
final class CancelEntry extends OutboxPlan {
  const CancelEntry(this.seq);

  final int seq;
}

/// Compactage de l'outbox (§4.3) — fonction pure, testée.
///
/// Règles :
/// 1. Rien en attente, ou l'entrée en attente a **déjà été tentée** : on
///    ajoute. Une entrée tentée a peut-être été appliquée par le serveur
///    (réponse perdue) ; la modifier ferait diverger l'idempotence.
/// 2. Création jamais envoyée puis suppression : on annule les deux.
/// 3. Sinon on fusionne : la nouvelle opération remplace l'ancienne, avec le
///    `base_version` **de la plus ancienne** et l'union des champs modifiés.
OutboxPlan planOutboxWrite(
  PendingOutboxEntry? pending,
  OutboxRequest incoming,
) {
  if (pending == null || pending.attempts > 0) return AppendEntry(incoming);

  final neverOnServer =
      pending.opType == OutboxOpType.upsert && pending.baseVersion == 0;
  if (incoming.opType == OutboxOpType.delete && neverOnServer) {
    return CancelEntry(pending.seq);
  }

  return ReplaceEntry(
    pending.seq,
    OutboxRequest(
      entity: incoming.entity,
      entityId: incoming.entityId,
      opType: incoming.opType,
      payload: incoming.payload,
      changedFields: {...pending.changedFields, ...incoming.changedFields},
      baseVersion: pending.baseVersion,
      userId: incoming.userId,
    ),
  );
}

/// Champs dont la valeur diffère entre deux instantanés.
Set<String> diffFields(
  Map<String, Object?> before,
  Map<String, Object?> after,
) => {
  for (final key in {...before.keys, ...after.keys})
    if (before[key] != after[key]) key,
};
