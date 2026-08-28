import '../database/app_database.dart';

class InventoryItem {
  final String medicine;
  final String batchNo;
  final DateTime expiryDate;
  final String supplier;
  final double purchaseRate;
  final double mrp;
  final double gstPercent;
  final int purchasedQuantity;
  final int soldQuantity;
  final int currentStock;

  const InventoryItem({
    required this.medicine,
    required this.batchNo,
    required this.expiryDate,
    required this.supplier,
    required this.purchaseRate,
    required this.mrp,
    required this.gstPercent,
    required this.purchasedQuantity,
    required this.soldQuantity,
    required this.currentStock,
  });

  String get stockStatus => currentStock > 0 ? 'In Stock' : 'Out of Stock';

  bool get isExpired => expiryDate.isBefore(DateTime.now());
}

class InventoryRepository {
  final AppDatabase database;

  InventoryRepository(this.database);

  Future<List<InventoryItem>> getAll() async {
    final medicines = await database.select(database.medicines).get();
    final suppliers = await database.select(database.suppliers).get();
    final batches = await database.select(database.batches).get();
    final purchaseItems = await database.select(database.purchaseItems).get();
    final movements = await database.select(database.stockMovements).get();

    final medicineNames = {
      for (final medicine in medicines) medicine.id: medicine.name,
    };
    final supplierNames = {
      for (final supplier in suppliers) supplier.id: supplier.name,
    };
    final purchaseItemsByBatch = <String, List<PurchaseItem>>{};
    for (final item in purchaseItems) {
      purchaseItemsByBatch.putIfAbsent(item.batchId, () => []).add(item);
    }

    final rows = <InventoryItem>[];
    for (final batch in batches) {
      final batchMovements = movements.where(
        (item) => item.batchId == batch.id,
      );
      var purchasedQuantity = 0;
      var soldQuantity = 0;
      var currentStock = 0;
      for (final movement in batchMovements) {
        if (movement.movementType == 'PURCHASE' ||
            movement.movementType == 'ADJUSTMENT_IN') {
          currentStock += movement.quantity;
        } else if (movement.movementType == 'SALE' ||
            movement.movementType == 'ADJUSTMENT_OUT') {
          currentStock -= movement.quantity;
        }
        if (movement.movementType == 'PURCHASE') {
          purchasedQuantity += movement.quantity;
        } else if (movement.movementType == 'SALE') {
          soldQuantity += movement.quantity;
        }
      }

      final batchPurchaseItems = purchaseItemsByBatch[batch.id] ?? const [];
      final purchasedItemQuantity = batchPurchaseItems.fold<int>(
        0,
        (total, item) => total + item.quantity,
      );
      final gstPercent = batchPurchaseItems.isEmpty
          ? 0.0
          : batchPurchaseItems.fold<double>(
                  0,
                  (total, item) => total + item.gstPercent * item.quantity,
                ) /
                (purchasedItemQuantity == 0 ? 1 : purchasedItemQuantity);

      rows.add(
        InventoryItem(
          medicine: medicineNames[batch.medicineId] ?? 'Unknown medicine',
          batchNo: batch.batchNo,
          expiryDate: batch.expiryDate,
          supplier: batch.supplierId == null
              ? '-'
              : supplierNames[batch.supplierId] ?? 'Unknown supplier',
          purchaseRate: batch.purchaseRate,
          mrp: batch.mrp,
          gstPercent: gstPercent,
          purchasedQuantity: purchasedQuantity,
          soldQuantity: soldQuantity,
          currentStock: currentStock,
        ),
      );
    }

    rows.sort((a, b) {
      final medicineOrder = a.medicine.compareTo(b.medicine);
      return medicineOrder == 0
          ? a.batchNo.compareTo(b.batchNo)
          : medicineOrder;
    });
    return rows;
  }
}
