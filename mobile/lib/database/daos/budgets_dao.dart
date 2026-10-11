import 'package:drift/drift.dart';

import '../../core/utils/local_date.dart';
import '../app_database.dart';
import '../tables/budgets_table.dart';

part 'budgets_dao.g.dart';

@DriftAccessor(tables: [Budgets])
class BudgetsDao extends DatabaseAccessor<AppDatabase> with _$BudgetsDaoMixin {
  BudgetsDao(super.attachedDatabase);

  /// Budget global applicable à [period] : celui du mois, sinon le plus
  /// récent des mois précédents (reconduction automatique, §3.I).
  Stream<BudgetRow?> watchEffective(String? userId, YearMonth period) =>
      _effective(userId, period).watchSingleOrNull();

  Future<BudgetRow?> getEffective(String? userId, YearMonth period) =>
      _effective(userId, period).getSingleOrNull();

  /// Budget global défini exactement pour [period], s'il existe.
  Future<BudgetRow?> findForPeriod(String? userId, YearMonth period) =>
      (select(budgets)..where(
            (b) =>
                b.deletedAt.isNull() &
                ownedBy(b.userId, userId) &
                b.categoryId.isNull() &
                b.period.equals(period.toIso()),
          ))
          .getSingleOrNull();

  Future<BudgetRow?> findById(String id) =>
      (select(budgets)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// Budget actif du compte pour `(période, catégorie)`, **sous un autre
  /// identifiant** que [excludingId].
  ///
  /// Sert au rapprochement par clé métier : deux téléphones peuvent créer le
  /// budget du même mois chacun de leur côté, donc avec des UUID différents.
  /// Le serveur fait autorité, la ligne locale cède la place.
  Future<BudgetRow?> findColliding(
    String userId,
    String period,
    String? categoryId, {
    String? excludingId,
  }) =>
      (select(budgets)..where(
            (b) =>
                b.deletedAt.isNull() &
                ownedBy(b.userId, userId) &
                b.period.equals(period) &
                (categoryId == null
                    ? b.categoryId.isNull()
                    : b.categoryId.equals(categoryId)) &
                (excludingId == null
                    ? const Constant(true)
                    : b.id.equals(excludingId).not()),
          ))
          .getSingleOrNull();

  SimpleSelectStatement<$BudgetsTable, BudgetRow> _effective(
    String? userId,
    YearMonth period,
  ) => select(budgets)
    ..where(
      (b) =>
          b.deletedAt.isNull() &
          ownedBy(b.userId, userId) &
          b.categoryId.isNull() &
          b.period.isSmallerOrEqualValue(period.toIso()),
    )
    ..orderBy([(b) => OrderingTerm.desc(b.period)])
    ..limit(1);
}
