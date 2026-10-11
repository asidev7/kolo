import '../../../core/constants/currencies.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../categories/domain/category.dart';
import 'transaction.dart';

/// Validation métier d'une opération (§3.E). Fonction pure : aucun accès à
/// la base ni à l'horloge, tout est passé en paramètre.
abstract final class TransactionValidator {
  static const amountField = 'amount';
  static const categoryField = 'category';
  static const noteField = 'note';
  static const dateField = 'occurredOn';

  /// Nombre de jours dans le futur autorisés (J+1).
  static const int maxDaysAhead = 1;

  /// Retourne les erreurs par champ ; vide si la saisie est valide.
  ///
  /// [category] est la catégorie choisie, chargée par l'appelant (`null` si
  /// introuvable). [allowArchivedCategory] autorise une catégorie archivée
  /// quand elle était déjà celle de l'opération modifiée.
  static Map<String, String> validate(
    TransactionDraft draft, {
    required LocalDate today,
    required KoloCategory? category,
    bool allowArchivedCategory = false,
    Currency currency = Currencies.xof,
  }) {
    final errors = <String, String>{};

    final amountError = validateAmount(draft.amount, currency: currency);
    if (amountError != null) errors[amountField] = amountError;

    if (draft.categoryId == null) {
      errors[categoryField] = 'Choisis une catégorie.';
    } else if (category == null) {
      errors[categoryField] =
          "Cette catégorie n'existe plus. Choisis-en une autre.";
    } else if (category.type != draft.type) {
      errors[categoryField] =
          "Cette catégorie ne correspond pas au type d'opération.";
    } else if (category.isArchived && !allowArchivedCategory) {
      errors[categoryField] = 'Cette catégorie a été archivée.';
    }

    final note = draft.normalizedNote;
    if (note != null && note.length > kMaxNoteLength) {
      errors[noteField] =
          'La note ne doit pas dépasser $kMaxNoteLength caractères.';
    }

    if (draft.occurredOn.isAfter(today.addDays(maxDaysAhead))) {
      errors[dateField] =
          'La date ne peut pas dépasser demain. Vérifie la date saisie.';
    }

    return errors;
  }

  static String? validateAmount(int? amount, {Currency currency = Currencies.xof}) {
    if (amount == null) return 'Saisis un montant.';
    if (amount <= 0) return 'Le montant doit être supérieur à 0.';
    if (amount > kMaxAmount) {
      return 'Le montant ne peut pas dépasser '
          '${formatMoney(kMaxAmount, currency: currency)}.';
    }
    return null;
  }
}
