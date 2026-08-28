import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/controllers/dashboard_controller.dart';
import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/dashboard_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dashboard controller loads a summary', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = DashboardRepository(database);
    final controller = DashboardController(repository);

    final summary = await controller.loadThisMonth();

    expect(summary.totalSales, 0.0);
    expect(summary.totalPurchases, 0.0);
    expect(summary.customerDue, 0.0);
    expect(summary.supplierDue, 0.0);
    expect(summary.totalExpenses, 0.0);
    expect(summary.currentStock, 0);
    expect(summary.grossProfit, 0.0);
    expect(summary.netProfit, 0.0);

    await database.close();
  });
}
