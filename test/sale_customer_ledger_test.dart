import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/batch_repository.dart';
import 'package:mm_lifecare_inventory/repositories/customer_repository.dart';
import 'package:mm_lifecare_inventory/repositories/medicine_repository.dart';
import 'package:mm_lifecare_inventory/repositories/purchase_repository.dart';
import 'package:mm_lifecare_inventory/repositories/sale_repository.dart';
import 'package:mm_lifecare_inventory/repositories/stock_repository.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sale with partial payment creates correct customer due', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final medicineRepository = MedicineRepository(database);
    final supplierRepository = SupplierRepository(database);
    final batchRepository = BatchRepository(database);
    final purchaseRepository = PurchaseRepository(database);
    final stockRepository = StockRepository(database);
    final saleRepository = SaleRepository(database, stockRepository);
    final customerRepository = CustomerRepository(database);

    const medicineId = 'medicine-001';
    const supplierId = 'supplier-001';
    const batchId = 'batch-001';
    const customerId = 'customer-001';

    // Create medicine.
    await medicineRepository.insertMedicine(
      id: medicineId,
      name: 'Paracetamol 500 mg',
      gstPercent: 5,
    );

    // Create supplier.
    await supplierRepository.insertSupplier(
      id: supplierId,
      name: 'ABC Pharma Distributors',
    );

    // Create batch.
    await batchRepository.insertBatch(
      id: batchId,
      medicineId: medicineId,
      supplierId: supplierId,
      batchNo: 'PCM001',
      expiryDate: DateTime(2028, 12, 31),
      purchaseRate: 10.0,
      mrp: 15.0,
    );

    // Purchase 100 units.
    await purchaseRepository.createPurchase(
      purchaseId: 'purchase-001',
      supplierId: supplierId,
      purchaseDate: DateTime(2026, 8, 12),
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

    // Create customer.
    await customerRepository.insertCustomer(
      id: customerId,
      name: 'Test Customer',
    );

    // Sale: 10 × ₹15 = ₹150.
    // GST 5% = ₹7.50.
    // Total = ₹157.50.
    // Customer pays ₹100.
    // Due = ₹57.50.
    await saleRepository.createSale(
      saleId: 'sale-001',
      invoiceNo: 'SALE-001',
      customerId: customerId,
      saleDate: DateTime(2026, 8, 12),
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

    // Customer due should be ₹57.50.
    final due = await customerRepository.getDue(customerId);

    expect(due, closeTo(57.50, 0.001));

    // Customer pays another ₹50.
    await customerRepository.recordPayment(
      paymentId: 'payment-001',
      customerId: customerId,
      amount: 50.0,
      paymentDate: DateTime(2026, 8, 12),
    );

    // Remaining due = ₹7.50.
    final remainingDue = await customerRepository.getDue(customerId);

    expect(remainingDue, closeTo(7.50, 0.001));

    // Stock should be 90.
    final stock = await stockRepository.getBatchStock(batchId);

    expect(stock, 90);

    await database.close();
  });
}
