import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/model/enums.dart';
import 'package:kolo/core/utils/local_date.dart';
import 'package:kolo/features/categories/domain/category.dart';
import 'package:kolo/features/transactions/domain/transaction.dart';
import 'package:kolo/features/transactions/domain/transaction_validator.dart';

const today = LocalDate(2026, 10, 9);

const food = KoloCategory(
  id: 'food',
  name: 'Alimentation',
  type: TransactionType.expense,
  icon: 'food',
  isDefault: true,
  isArchived: false,
);

const salary = KoloCategory(
  id: 'salary',
  name: 'Salaire',
  type: TransactionType.income,
  icon: 'salary',
  isDefault: true,
  isArchived: false,
);

TransactionDraft draft({
  int? amount = 1500,
  String? categoryId = 'food',
  TransactionType type = TransactionType.expense,
  String? note,
  LocalDate occurredOn = today,
}) => TransactionDraft(
  type: type,
  amount: amount,
  categoryId: categoryId,
  note: note,
  occurredOn: occurredOn,
);

Map<String, String> validate(
  TransactionDraft d, {
  KoloCategory? category = food,
  bool allowArchived = false,
}) => TransactionValidator.validate(
  d,
  today: today,
  category: category,
  allowArchivedCategory: allowArchived,
);

void main() {
  test('une saisie complète est valide', () {
    expect(validate(draft()), isEmpty);
  });

  group('montant', () {
    test('vide', () {
      expect(validate(draft(amount: null)), contains('amount'));
    });

    test('nul ou négatif', () {
      expect(validate(draft(amount: 0))['amount'], contains('supérieur à 0'));
      expect(validate(draft(amount: -10))['amount'], contains('supérieur à 0'));
    });

    test('plafond de sécurité inclus, dépassement refusé', () {
      expect(validate(draft(amount: 999999999999)), isEmpty);
      expect(validate(draft(amount: 1000000000000)), contains('amount'));
    });
  });

  group('catégorie', () {
    test('obligatoire', () {
      expect(
        validate(draft(categoryId: null), category: null),
        contains('category'),
      );
    });

    test('doit correspondre au type', () {
      final errors = validate(
        draft(type: TransactionType.income, categoryId: 'food'),
      );
      expect(errors['category'], contains('ne correspond pas'));
      expect(
        validate(
          draft(type: TransactionType.income, categoryId: 'salary'),
          category: salary,
        ),
        isEmpty,
      );
    });

    test('introuvable', () {
      expect(validate(draft(), category: null), contains('category'));
    });

    test("archivée : refusée en création, acceptée si elle était déjà celle de l'opération", () {
      const archived = KoloCategory(
        id: 'food',
        name: 'Alimentation',
        type: TransactionType.expense,
        icon: 'food',
        isDefault: false,
        isArchived: true,
      );
      expect(validate(draft(), category: archived), contains('category'));
      expect(
        validate(draft(), category: archived, allowArchived: true),
        isEmpty,
      );
    });
  });

  test('note de 140 caractères maximum, espaces ignorés', () {
    expect(validate(draft(note: 'a' * 140)), isEmpty);
    expect(validate(draft(note: '  ${'a' * 140}  ')), isEmpty);
    expect(validate(draft(note: 'a' * 141)), contains('note'));
  });

  test('date : jusqu\'à J+1 autorisée, au-delà refusée', () {
    expect(validate(draft(occurredOn: today.addDays(1))), isEmpty);
    expect(
      validate(draft(occurredOn: today.addDays(2))),
      contains('occurredOn'),
    );
    expect(validate(draft(occurredOn: const LocalDate(2020, 1, 1))), isEmpty);
  });

  test('normalizedNote', () {
    expect(draft(note: '   ').normalizedNote, isNull);
    expect(draft(note: ' Zém ').normalizedNote, 'Zém');
  });
}
