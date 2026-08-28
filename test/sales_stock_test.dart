import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/batch_repository.dart';
import 'package:mm_lifecare_inventory/repositories/medicine_repository.dart';
import 'package:mm_lifecare_inventory/repositories/purchase_repository.dart';
import 'package:mm_lifecare_inventory/repositories/sale_repository.dart';
import 'package:mm_lifecare_inventory/repositories/stock_repository.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('purchase 100, sell 15, stock becomes 85', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final medicineRepository = MedicineRepository(database);
    final supplierRepository = SupplierRepository(database);
    final batchRepository = BatchRepository(database);
    final purchaseRepository = PurchaseRepository(database);
    final stockRepository = StockRepository(database);
    final saleRepository = SaleRepository(database, stockRepository);

    const medicineId = 'medicine-001';
    const supplierId = 'supplier-001';
    const batchId = 'batch-001';

    // 1. Create medicine.
    await medicineRepository.insertMedicine(
      id: medicineId,
      name: 'Paracetamol 500 mg',
      gstPercent: 5,
      minimumStock: 20,
      suggestedOrderQty: 100,
    );

    // 2. Create supplier.
    await supplierRepository.insertSupplier(
      id: supplierId,
      name: 'ABC Pharma Distributors',
    );

    // 3. Create batch.
    await batchRepository.insertBatch(
      id: batchId,
      medicineId: medicineId,
      supplierId: supplierId,
      batchNo: 'PCM001',
      expiryDate: DateTime(2028, 12, 31),
      purchaseRate: 10.0,
      mrp: 15.0,
    );

    // 4. Purchase 100 units.
    await purchaseRepository.createPurchase(
      purchaseId: 'purchase-001',
      invoiceNo: 'PUR-001',
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

    // 5. Verify stock = 100.
    var stock = await stockRepository.getBatchStock(batchId);

    expect(stock, 100);

    // 6. Sell 15 units.
    await saleRepository.createSale(
      saleId: 'sale-001',
      invoiceNo: 'SALE-001',
      saleDate: DateTime(2026, 8, 12),
      items: const [
        SaleItemData(
          id: 'sale-item-001',
          medicineId: medicineId,
          batchId: batchId,
          quantity: 15,
          saleRate: 15.0,
          mrp: 15.0,
          gstPercent: 5.0,
        ),
      ],
      paidAmount: 236.25,
    );

    // 7. Verify stock = 85.
    stock = await stockRepository.getBatchStock(batchId);

    expect(stock, 85);

    // 8. Verify medicine-level stock = 85.
    final medicineStock = await stockRepository.getMedicineStock(medicineId);

    expect(medicineStock, 85);

    await database.close();
  });

  test('sale is rejected when quantity exceeds stock', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final medicineRepository = MedicineRepository(database);
    final supplierRepository = SupplierRepository(database);
    final batchRepository = BatchRepository(database);
    final purchaseRepository = PurchaseRepository(database);
    final stockRepository = StockRepository(database);
    final saleRepository = SaleRepository(database, stockRepository);

    const medicineId = 'medicine-002';
    const supplierId = 'supplier-002';
    const batchId = 'batch-002';

    await medicineRepository.insertMedicine(
      id: medicineId,
      name: 'Test Medicine',
    );

    await supplierRepository.insertSupplier(
      id: supplierId,
      name: 'Test Supplier',
    );

    await batchRepository.insertBatch(
      id: batchId,
      medicineId: medicineId,
      supplierId: supplierId,
      batchNo: 'TEST001',
      expiryDate: DateTime(2028, 12, 31),
      purchaseRate: 10.0,
      mrp: 15.0,
    );

    // Only 10 units available.
    await purchaseRepository.createPurchase(
      purchaseId: 'purchase-002',
      supplierId: supplierId,
      purchaseDate: DateTime(2026, 8, 12),
      items: const [
        PurchaseItemData(
          id: 'purchase-item-002',
          medicineId: medicineId,
          batchId: batchId,
          quantity: 10,
          purchaseRate: 10.0,
          mrp: 15.0,
          gstPercent: 5.0,
        ),
      ],
    );

    // Attempt to sell 15.
    expect(
      () => saleRepository.createSale(
        saleId: 'sale-002',
        saleDate: DateTime(2026, 8, 12),
        items: const [
          SaleItemData(
            id: 'sale-item-002',
            medicineId: medicineId,
            batchId: batchId,
            quantity: 15,
            saleRate: 15.0,
            mrp: 15.0,
            gstPercent: 5.0,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    // Stock must remain 10.
    final stock = await stockRepository.getBatchStock(batchId);

    expect(stock, 10);

    await database.close();
  });
}
