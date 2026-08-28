import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/expense_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('expenses can be added and totals calculated', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = ExpenseRepository(database);

    final date = DateTime(2026, 8, 12);

    await repository.addExpense(
      id: 'expense-001',
      category: 'Rent',
      particulars: 'Shop rent',
      amount: 5000.0,
      expenseDate: date,
    );

    await repository.addExpense(
      id: 'expense-002',
      category: 'Electricity',
      particulars: 'Electricity bill',
      amount: 2000.0,
      expenseDate: date,
    );

    await repository.addExpense(
      id: 'expense-003',
      category: 'Transport',
      particulars: 'Medicine delivery',
      amount: 1000.0,
      expenseDate: date,
    );

    final total = await repository.getTotalExpenses();

    expect(total, 8000.0);

    final rentTotal = await repository.getCategoryTotal('Rent');

    expect(rentTotal, 5000.0);

    final electricityTotal = await repository.getCategoryTotal('Electricity');

    expect(electricityTotal, 2000.0);

    final expenses = await repository.getAll();

    expect(expenses.length, 3);

    await database.close();
  });
}
