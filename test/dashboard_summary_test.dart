import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/batch_repository.dart';
import 'package:mm_lifecare_inventory/repositories/customer_repository.dart';
import 'package:mm_lifecare_inventory/repositories/dashboard_repository.dart';
import 'package:mm_lifecare_inventory/repositories/expense_repository.dart';
import 'package:mm_lifecare_inventory/repositories/medicine_repository.dart';
import 'package:mm_lifecare_inventory/repositories/purchase_repository.dart';
import 'package:mm_lifecare_inventory/repositories/sale_repository.dart';
import 'package:mm_lifecare_inventory/repositories/stock_repository.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dashboard summary calculates correctly', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final medicineRepository = MedicineRepository(database);
    final supplierRepository = SupplierRepository(database);
    final batchRepository = BatchRepository(database);
    final purchaseRepository = PurchaseRepository(database);
    final stockRepository = StockRepository(database);
    final saleRepository = SaleRepository(database, stockRepository);
    final customerRepository = CustomerRepository(database);
    final expenseRepository = ExpenseRepository(database);
    final dashboardRepository = DashboardRepository(database);

    const medicineId = 'medicine-001';
    const supplierId = 'supplier-001';
    const batchId = 'batch-001';
    const customerId = 'customer-001';

    final date = DateTime(2026, 8, 12);

    // Medicine.
    await medicineRepository.insertMedicine(
      id: medicineId,
      name: 'Paracetamol 500 mg',
      gstPercent: 5,
    );

    // Supplier.
    await supplierRepository.insertSupplier(
      id: supplierId,
      name: 'ABC Pharma Distributors',
    );

    // Batch.
    await batchRepository.insertBatch(
      id: batchId,
      medicineId: medicineId,
      supplierId: supplierId,
      batchNo: 'PCM001',
      expiryDate: DateTime(2028, 12, 31),
      purchaseRate: 10.0,
      mrp: 15.0,
    );

    // Purchase 100 × ₹10 + 5% GST.
    await purchaseRepository.createPurchase(
      purchaseId: 'purchase-001',
      invoiceNo: 'PUR-001',
      supplierId: supplierId,
      purchaseDate: date,
      items: const [
        PurchaseItemData(
          id: 'purchase-item-001',
          medicineId: medicineId,
          batchId: batchId,
          quantity: 100,
          purchaseRate: 10.0,
          mrp: 15.0,
          gstPercent: 5.0,
        ),
      ],
    );

    // Customer.
    await customerRepository.insertCustomer(
      id: customerId,
      name: 'Test Customer',
    );

    // Sale 10 × ₹15 + 5% GST.
    // Subtotal = ₹150
    // GST = ₹7.50
    // Total = ₹157.50
    // Paid = ₹100
    // Due = ₹57.50
    await saleRepository.createSale(
      saleId: 'sale-001',
      invoiceNo: 'SALE-001',
      customerId: customerId,
      saleDate: date,
      items: const [
        SaleItemData(
          id: 'sale-item-001',
          medicineId: medicineId,
          batchId: batchId,
          quantity: 10,
          saleRate: 15.0,
          mrp: 15.0,
          gstPercent: 5.0,
        ),
      ],
      paidAmount: 100.0,
    );

    // Expense = ₹1,000.
    await expenseRepository.addExpense(
      id: 'expense-001',
      category: 'Rent',
      particulars: 'Shop rent',
      amount: 1000.0,
      expenseDate: date,
    );

    final summary = await dashboardRepository.getSummary();

    expect(summary.totalSales, closeTo(157.50, 0.001));

    expect(summary.totalPurchases, closeTo(1050.00, 0.001));

    expect(summary.customerDue, closeTo(57.50, 0.001));

    expect(summary.supplierDue, closeTo(1050.00, 0.001));

    expect(summary.totalExpenses, closeTo(1000.00, 0.001));

    expect(summary.currentStock, 90);

    // Revenue = ₹157.50
    // COGS = 10 × ₹10 = ₹100
    // Gross profit = ₹57.50
    expect(summary.grossProfit, closeTo(57.50, 0.001));

    // Net profit = ₹57.50 - ₹1,000
    // = -₹942.50
    expect(summary.netProfit, closeTo(-942.50, 0.001));

    await database.close();
  });
}
