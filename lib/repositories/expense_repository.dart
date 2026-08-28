import 'package:drift/drift.dart';

import '../database/app_database.dart';

class ExpenseRepository {
  final AppDatabase database;

  ExpenseRepository(this.database);

  Future<List<Expense>> getAll() {
    return (database.select(database.expenses)..orderBy([
          (tbl) => OrderingTerm(
            expression: tbl.expenseDate,
            mode: OrderingMode.desc,
          ),
        ]))
        .get();
  }

  Future<List<Expense>> getByCategory(String category) {
    return (database.select(database.expenses)
          ..where((tbl) => tbl.category.equals(category))
          ..orderBy([
            (tbl) => OrderingTerm(
              expression: tbl.expenseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  Future<void> addExpense({
    required String id,
    required String category,
    String? particulars,
    required double amount,
    required DateTime expenseDate,
    String paymentMethod = 'CASH',
    String? referenceNo,
    String? notes,
  }) async {
    await database
        .into(database.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            category: category,
            particulars: Value(particulars),
            amount: Value(amount),
            expenseDate: expenseDate,
            paymentMethod: Value(paymentMethod),
            referenceNo: Value(referenceNo),
            notes: Value(notes),
          ),
        );
  }

  Future<void> deleteExpense(String id) async {
    await (database.delete(
      database.expenses,
    )..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<double> getTotalExpenses() async {
    final expenses = await database.select(database.expenses).get();

    double total = 0.0;

    for (final expense in expenses) {
      total += expense.amount;
    }

    return total;
  }

  Future<double> getCategoryTotal(String category) async {
    final expenses = await getByCategory(category);

    double total = 0.0;

    for (final expense in expenses) {
      total += expense.amount;
    }

    return total;
  }
}
