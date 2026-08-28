import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/batch_repository.dart';
import 'package:mm_lifecare_inventory/repositories/medicine_repository.dart';
import 'package:mm_lifecare_inventory/repositories/purchase_repository.dart';
import 'package:mm_lifecare_inventory/repositories/stock_repository.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('purchase creates stock correctly', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final medicineRepository = MedicineRepository(database);
    final supplierRepository = SupplierRepository(database);
    final batchRepository = BatchRepository(database);
    final purchaseRepository = PurchaseRepository(database);
    final stockRepository = StockRepository(database);

    const medicineId = 'medicine-001';
    const supplierId = 'supplier-001';
    const batchId = 'batch-001';

    // Create medicine.
    await medicineRepository.insertMedicine(
      id: medicineId,
      name: 'Paracetamol 500 mg',
      gstPercent: 5,
      minimumStock: 20,
      suggestedOrderQty: 100,
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

    // Create purchase.
    await purchaseRepository.createPurchase(
      purchaseId: 'purchase-001',
      invoiceNo: 'INV-001',
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

    // Check stock.
    final batchStock = await stockRepository.getBatchStock(batchId);

    final medicineStock = await stockRepository.getMedicineStock(medicineId);

    expect(batchStock, 100);
    expect(medicineStock, 100);

    await database.close();
  });
}
