import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/dashboard_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dashboard date range includes only transactions in range', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = DashboardRepository(database);

    final aug11 = DateTime(2026, 8, 11);
    final aug12 = DateTime(2026, 8, 12);
    final aug13 = DateTime(2026, 8, 13);

    // Sales on 11, 12 and 13 August.
    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale-11',
            saleDate: aug11,
            totalAmount: const Value(100.0),
          ),
        );

    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale-12',
            saleDate: aug12,
            totalAmount: const Value(200.0),
          ),
        );

    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale-13',
            saleDate: aug13,
            totalAmount: const Value(300.0),
          ),
        );

    // Expenses on 11, 12 and 13 August.
    await database
        .into(database.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: 'expense-11',
            category: 'Rent',
            amount: const Value(50.0),
            expenseDate: aug11,
          ),
        );

    await database
        .into(database.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: 'expense-12',
            category: 'Electricity',
            amount: const Value(75.0),
            expenseDate: aug12,
          ),
        );

    await database
        .into(database.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: 'expense-13',
            category: 'Transport',
            amount: const Value(100.0),
            expenseDate: aug13,
          ),
        );

    // Range: 11 Aug inclusive → 13 Aug exclusive.
    //
    // Therefore:
    // 11 Aug = included
    // 12 Aug = included
    // 13 Aug = excluded

    final summary = await repository.getSummary(from: aug11, to: aug13);

    expect(summary.totalSales, closeTo(300.0, 0.001));

    expect(summary.totalExpenses, closeTo(125.0, 0.001));

    // No sale items exist, therefore COGS = 0.
    // Gross profit = sales = ₹300.
    expect(summary.grossProfit, closeTo(300.0, 0.001));

    // Net profit = ₹300 - ₹125 = ₹175.
    expect(summary.netProfit, closeTo(175.0, 0.001));

    await database.close();
  });
}
