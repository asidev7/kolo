import 'dart:convert';

import 'package:meta/meta.dart';

import '../../core/errors/failures.dart';
import '../../core/model/enums.dart';
import '../../core/network/json_reader.dart';
import '../../database/app_database.dart';

/// Objets échangés avec `/sync/` (§4.4), écrits à la main (D30).
///
/// Aucun `fromJson` ne fait confiance au réseau : une forme inattendue devient
/// une [ApiFailure] `invalid_response`, jamais une exception Dart brute.
///
/// Référence du contrat : `docs/API.md` §Synchronisation et
/// `backend/apps/sync/service.py`.

// ---------------------------------------------------------------------------
// Push
// ---------------------------------------------------------------------------

/// Une opération d'outbox prête à partir.
@immutable
class PushOperation {
  const PushOperation({
    required this.opId,
    required this.entity,
    required this.entityId,
    required this.opType,
    required this.baseVersion,
    required this.changedFields,
    required this.data,
  });

  /// Traduit une entrée d'outbox. `payload` et `changed_fields` sont les
  /// colonnes JSON écrites par `OutboxWriter` : elles sont relues ici, jamais
  /// reconstruites, pour que le serveur voie exactement ce qui a été validé.
  factory PushOperation.fromEntry(OutboxEntry entry) => PushOperation(
    opId: entry.opId,
    entity: entry.entity,
    entityId: entry.entityId,
    opType: entry.opType,
    baseVersion: entry.baseVersion,
    changedFields: decodeStringList(entry.changedFields),
    data: decodeJsonObject(entry.payload),
  );

  final String opId;
  final SyncEntity entity;
  final String entityId;
  final OutboxOpType opType;
  final int baseVersion;
  final List<String> changedFields;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'op_id': opId,
    'entity': entity.wire,
    'entity_id': entityId,
    'op_type': opType.wire,
    'base_version': baseVersion,
    'changed_fields': changedFields,
    'data': data,
  };
}

/// Résultat d'une opération, dans l'ordre reçu.
sealed class PushOutcome {
  const PushOutcome({
    required this.opId,
    required this.entity,
    required this.entityId,
  });

  factory PushOutcome.fromJson(Map<String, Object?> json) {
    final opId = json.requireString('op_id');
    final entity = entityFromWire(json.requireString('entity'));
    final entityId = json.requireString('entity_id');
    final status = json.requireString('status');
    return switch (status) {
      'applied' || 'duplicate' => PushApplied(
        opId: opId,
        entity: entity,
        entityId: entityId,
        version: json.requireInt('version'),
        serverUpdatedAt: parseServerDate(
          json.optionalString('server_updated_at'),
        ),
        deletedAt: parseServerDate(json.optionalString('deleted_at')),
        wasDuplicate: status == 'duplicate',
      ),
      'conflict' => PushConflict(
        opId: opId,
        entity: entity,
        entityId: entityId,
        reason: json.requireString('reason'),
        conflictingFields: json.optionalStringList('conflicting_fields'),
        serverRecord: ServerRecord.fromJson(json.requireMap('server_record')),
      ),
      'rejected' => PushRejected(
        opId: opId,
        entity: entity,
        entityId: entityId,
        code: json.requireMap('error').requireString('code'),
      ),
      _ => throw ApiFailure(
        code: 'invalid_response',
        message: 'Réponse inattendue du serveur.',
        fields: {'status': status},
      ),
    };
  }

  final String opId;
  final SyncEntity entity;
  final String entityId;
}

/// L'opération a été appliquée (ou l'avait déjà été : `wasDuplicate`).
///
/// `version == 0` avec `deletedAt` renseigné signifie que le serveur ne
/// connaissait pas l'enregistrement : il n'y a aucune version à adopter.
final class PushApplied extends PushOutcome {
  const PushApplied({
    required super.opId,
    required super.entity,
    required super.entityId,
    required this.version,
    required this.serverUpdatedAt,
    required this.deletedAt,
    this.wasDuplicate = false,
  });

  final int version;
  final DateTime? serverUpdatedAt;
  final DateTime? deletedAt;
  final bool wasDuplicate;
}

/// Le serveur a modifié les mêmes champs : l'utilisateur tranche (§5).
final class PushConflict extends PushOutcome {
  const PushConflict({
    required super.opId,
    required super.entity,
    required super.entityId,
    required this.reason,
    required this.conflictingFields,
    required this.serverRecord,
  });

  final String reason;
  final List<String> conflictingFields;
  final ServerRecord serverRecord;
}

/// Refus définitif : l'entrée d'outbox passe en `failed` et reste affichée.
final class PushRejected extends PushOutcome {
  const PushRejected({
    required super.opId,
    required super.entity,
    required super.entityId,
    required this.code,
  });

  /// `validation_error`, `unknown_category`, `duplicate_budget`, …
  final String code;
}

/// Réponse complète de `POST /sync/push`.
@immutable
class PushResponse {
  const PushResponse({required this.results, required this.serverTime});

  factory PushResponse.fromJson(Map<String, Object?> json) => PushResponse(
    results: [
      for (final result in json.optionalMapList('results'))
        PushOutcome.fromJson(result),
    ],
    serverTime: parseServerDate(json.optionalString('server_time')),
  );

  final List<PushOutcome> results;
  final DateTime? serverTime;
}

// ---------------------------------------------------------------------------
// Pull
// ---------------------------------------------------------------------------

/// Enregistrement tel que le serveur le connaît — même forme dans
/// `sync/pull` et dans `server_record` d'un conflit.
@immutable
class ServerRecord {
  const ServerRecord({
    required this.entity,
    required this.entityId,
    required this.version,
    required this.serverUpdatedAt,
    required this.deletedAt,
    required this.changeSeq,
    required this.data,
  });

  factory ServerRecord.fromJson(Map<String, Object?> json) => ServerRecord(
    entity: entityFromWire(json.requireString('entity')),
    entityId: json.requireString('entity_id'),
    version: json.requireInt('version'),
    serverUpdatedAt: parseServerDate(json.optionalString('server_updated_at')),
    deletedAt: parseServerDate(json.optionalString('deleted_at')),
    changeSeq: json.optionalInt('change_seq'),
    data: json.optionalMap('data') ?? const {},
  );

  final SyncEntity entity;
  final String entityId;
  final int version;
  final DateTime? serverUpdatedAt;

  /// Renseigné pour un tombstone : l'enregistrement est supprimé côté serveur.
  final DateTime? deletedAt;
  final int? changeSeq;
  final Map<String, Object?> data;

  bool get isDeleted => deletedAt != null;
}

/// Une page de `GET /sync/pull`.
@immutable
class PullPage {
  const PullPage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
    required this.serverTime,
  });

  factory PullPage.fromJson(Map<String, Object?> json) => PullPage(
    changes: [
      for (final change in json.optionalMapList('changes'))
        ServerRecord.fromJson(change),
    ],
    nextCursor: json.requireString('next_cursor'),
    hasMore: json.optionalBool('has_more') ?? false,
    serverTime: parseServerDate(json.optionalString('server_time')),
  );

  final List<ServerRecord> changes;
  final String nextCursor;
  final bool hasMore;
  final DateTime? serverTime;
}

// ---------------------------------------------------------------------------
// Outils
// ---------------------------------------------------------------------------

/// Le serveur a purgé son journal : le curseur local n'a plus de sens.
///
/// Volontairement **pas** un [Failure] : ce n'est pas une panne mais une
/// consigne de reprise (`cursor = 0`, pull complet), que le moteur traite
/// comme un cas normal.
class CursorResetRequired implements Exception {
  const CursorResetRequired();

  @override
  String toString() => 'CursorResetRequired';
}

/// Horodatage serveur : toujours normalisé en UTC.
///
/// Drift stocke les dates en texte ISO-8601 : la comparaison des chaînes doit
/// rester l'ordre chronologique, donc jamais de date locale mêlée aux dates
/// serveur.
DateTime? parseServerDate(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw ApiFailure(
      code: 'invalid_response',
      message: 'Réponse inattendue du serveur.',
      fields: {'date': value},
    );
  }
}

/// Entité inconnue = application plus ancienne que le serveur : on échoue
/// bruyamment plutôt que d'ignorer silencieusement des données.
SyncEntity entityFromWire(String value) {
  for (final entity in SyncEntity.values) {
    if (entity.wire == value) return entity;
  }
  throw ApiFailure(
    code: 'invalid_response',
    message: 'Réponse inattendue du serveur.',
    fields: {'entity': value},
  );
}

/// Relit une liste JSON de chaînes écrite par l'outbox.
List<String> decodeStringList(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List<Object?>) return const [];
  return decoded.whereType<String>().toList(growable: false);
}

/// Relit un objet JSON écrit par l'outbox.
Map<String, Object?> decodeJsonObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<Object?, Object?>) return const {};
  return {for (final entry in decoded.entries) '${entry.key}': entry.value};
}
