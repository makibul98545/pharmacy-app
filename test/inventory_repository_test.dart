import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/batch_repository.dart';
import 'package:mm_lifecare_inventory/repositories/inventory_repository.dart';
import 'package:mm_lifecare_inventory/repositories/medicine_repository.dart';
import 'package:mm_lifecare_inventory/repositories/purchase_repository.dart';
import 'package:mm_lifecare_inventory/repositories/sale_repository.dart';
import 'package:mm_lifecare_inventory/repositories/stock_repository.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'inventory reports separate batches and movement-based quantities',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final medicineRepository = MedicineRepository(database);
      final supplierRepository = SupplierRepository(database);
      final batchRepository = BatchRepository(database);
      final purchaseRepository = PurchaseRepository(database);
      final stockRepository = StockRepository(database);
      final saleRepository = SaleRepository(database, stockRepository);
      final inventoryRepository = InventoryRepository(database);

      await medicineRepository.insertMedicine(
        id: 'medicine-001',
        name: 'Paracetamol 500 mg',
        gstPercent: 5,
      );
      await supplierRepository.insertSupplier(
        id: 'supplier-001',
        name: 'ABC Pharma',
      );
      await batchRepository.insertBatch(
        id: 'batch-001',
        medicineId: 'medicine-001',
        supplierId: 'supplier-001',
        batchNo: 'PCM001',
        expiryDate: DateTime(2028, 12, 31),
        purchaseRate: 10,
        mrp: 15,
      );
      await batchRepository.insertBatch(
        id: 'batch-002',
        medicineId: 'medicine-001',
        supplierId: 'supplier-001',
        batchNo: 'PCM002',
        expiryDate: DateTime(2027, 12, 31),
        purchaseRate: 11,
        mrp: 16,
      );
      await purchaseRepository.createPurchase(
        purchaseId: 'purchase-001',
        supplierId: 'supplier-001',
        purchaseDate: DateTime(2026, 8, 12),
        items: const [
          PurchaseItemData(
            id: 'purchase-item-001',
            medicineId: 'medicine-001',
            batchId: 'batch-001',
            quantity: 100,
            purchaseRate: 10,
            mrp: 15,
            gstPercent: 5,
          ),
          PurchaseItemData(
            id: 'purchase-item-002',
            medicineId: 'medicine-001',
            batchId: 'batch-002',
            quantity: 40,
            purchaseRate: 11,
            mrp: 16,
            gstPercent: 12,
          ),
        ],
      );
      await saleRepository.createSale(
        saleId: 'sale-001',
        saleDate: DateTime(2026, 8, 13),
        items: const [
          SaleItemData(
            id: 'sale-item-001',
            medicineId: 'medicine-001',
            batchId: 'batch-001',
            quantity: 15,
            saleRate: 15,
            mrp: 15,
            gstPercent: 5,
          ),
        ],
      );

      final rows = await inventoryRepository.getAll();

      expect(rows, hasLength(2));
      expect(rows[0].batchNo, 'PCM001');
      expect(rows[0].purchasedQuantity, 100);
      expect(rows[0].soldQuantity, 15);
      expect(rows[0].currentStock, 85);
      expect(rows[0].stockStatus, 'In Stock');
      expect(rows[0].supplier, 'ABC Pharma');
      expect(rows[0].gstPercent, 5);
      expect(rows[1].batchNo, 'PCM002');
      expect(rows[1].purchasedQuantity, 40);
      expect(rows[1].soldQuantity, 0);
      expect(rows[1].currentStock, 40);

      await database.close();
    },
  );
}
