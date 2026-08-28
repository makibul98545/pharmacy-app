import 'package:drift/drift.dart';

import '../database/app_database.dart';

class PurchaseRepository {
  final AppDatabase database;

  PurchaseRepository(this.database);

  Future<void> createPurchase({
    required String purchaseId,
    String? invoiceNo,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemData> items,
    String? notes,
  }) async {
    await database.transaction(() async {
      double subtotal = 0;
      double gstAmount = 0;

      for (final item in items) {
        final baseAmount = item.quantity * item.purchaseRate;
        final itemGst = baseAmount * item.gstPercent / 100;
        final itemTotal = baseAmount + itemGst;

        subtotal += baseAmount;
        gstAmount += itemGst;

        await database
            .into(database.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                id: item.id,
                purchaseId: purchaseId,
                medicineId: item.medicineId,
                batchId: item.batchId,
                quantity: item.quantity,
                purchaseRate: Value(item.purchaseRate),
                mrp: Value(item.mrp),
                gstPercent: Value(item.gstPercent),
                gstAmount: Value(itemGst),
                totalAmount: Value(itemTotal),
              ),
            );

        await database
            .into(database.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: '${purchaseId}_${item.id}',
                medicineId: item.medicineId,
                batchId: item.batchId,
                movementType: 'PURCHASE',
                quantity: item.quantity,
                referenceId: Value(purchaseId),
                movementDate: purchaseDate,
              ),
            );
      }

      await database
          .into(database.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              invoiceNo: Value(invoiceNo),
              supplierId: supplierId,
              purchaseDate: purchaseDate,
              subtotal: Value(subtotal),
              gstAmount: Value(gstAmount),
              totalAmount: Value(subtotal + gstAmount),
              notes: Value(notes),
            ),
          );
    });
  }
}

class PurchaseItemData {
  final String id;
  final String medicineId;
  final String batchId;
  final int quantity;
  final double purchaseRate;
  final double mrp;
  final double gstPercent;

  const PurchaseItemData({
    required this.id,
    required this.medicineId,
    required this.batchId,
    required this.quantity,
    required this.purchaseRate,
    required this.mrp,
    required this.gstPercent,
  });
}
