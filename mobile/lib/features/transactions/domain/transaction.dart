import 'package:meta/meta.dart';

import '../../../core/model/enums.dart';
import '../../../core/utils/local_date.dart';

/// Opération enregistrée (§5.3).
@immutable
class KoloTransaction {
  const KoloTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.categoryId,
    required this.occurredOn,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    required this.syncStatus,
    this.userId,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String? userId;
  final TransactionType type;

  /// Entier strictement positif ; le signe vient de [type].
  final int amount;
  final String currency;
  final String categoryId;
  final String? note;
  final LocalDate occurredOn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;

  /// Effet signé sur le solde net.
  int get signedAmount => type == TransactionType.income ? amount : -amount;

  /// Pas encore confirmée par le serveur.
  bool get isPending =>
      syncStatus == SyncStatus.pending ||
      syncStatus == SyncStatus.conflict ||
      syncStatus == SyncStatus.failed;

  TransactionDraft toDraft() => TransactionDraft(
    type: type,
    amount: amount,
    categoryId: categoryId,
    note: note,
    occurredOn: occurredOn,
  );
}

/// Saisie en cours dans le formulaire, avant validation.
@immutable
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.occurredOn,
    this.amount,
    this.categoryId,
    this.note,
  });

  final TransactionType type;

  /// `null` si la saisie est vide ou illisible.
  final int? amount;
  final String? categoryId;
  final String? note;
  final LocalDate occurredOn;

  /// Note nettoyée : `null` si vide.
  String? get normalizedNote {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
