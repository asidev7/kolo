import 'package:meta/meta.dart';

/// Somme des revenus et des dépenses sur un intervalle.
@immutable
class TypeTotals {
  const TypeTotals({required this.income, required this.expense});

  static const zero = TypeTotals(income: 0, expense: 0);

  final int income;
  final int expense;

  @override
  bool operator ==(Object other) =>
      other is TypeTotals && other.income == income && other.expense == expense;

  @override
  int get hashCode => Object.hash(income, expense);

  @override
  String toString() => 'TypeTotals(income: $income, expense: $expense)';
}
