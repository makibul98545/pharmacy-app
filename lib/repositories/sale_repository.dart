import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'stock_repository.dart';

class SaleRepository {
  final AppDatabase database;
  final StockRepository stockRepository;

  SaleRepository(this.database, this.stockRepository);

  Future<void> createSale({
    required String saleId,
    String? invoiceNo,
    String? customerId,
    required DateTime saleDate,
    required List<SaleItemData> items,
    double discountAmount = 0.0,
    double paidAmount = 0.0,
    String? notes,
  }) async {
    await database.transaction(() async {
      double subtotal = 0.0;
      double gstAmount = 0.0;

      // Validate stock before changing anything.
      for (final item in items) {
        final currentStock = await stockRepository.getBatchStock(item.batchId);

        if (item.quantity > currentStock) {
          throw StateError(
            'Insufficient stock for batch ${item.batchId}. '
            'Available: $currentStock, requested: ${item.quantity}',
          );
        }
      }

      for (final item in items) {
        final baseAmount = item.quantity * item.saleRate;

        final itemGst = baseAmount * item.gstPercent / 100;

        final itemTotal = baseAmount + itemGst - item.discountAmount;

        subtotal += baseAmount;
        gstAmount += itemGst;

        await database
            .into(database.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                id: item.id,
                saleId: saleId,
                medicineId: item.medicineId,
                batchId: item.batchId,
                quantity: item.quantity,
                saleRate: Value(item.saleRate),
                mrp: Value(item.mrp),
                gstPercent: Value(item.gstPercent),
                gstAmount: Value(itemGst),
                discountAmount: Value(item.discountAmount),
                totalAmount: Value(itemTotal),
              ),
            );

        await database
            .into(database.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: '${saleId}_${item.id}',
                medicineId: item.medicineId,
                batchId: item.batchId,
                movementType: 'SALE',
                quantity: item.quantity,
                referenceId: Value(saleId),
                movementDate: saleDate,
              ),
            );
      }

      final totalAmount = subtotal + gstAmount - discountAmount;

      final dueAmount = totalAmount - paidAmount;

      await database
          .into(database.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              invoiceNo: Value(invoiceNo),
              customerId: Value(customerId),
              saleDate: saleDate,
              subtotal: Value(subtotal),
              gstAmount: Value(gstAmount),
              discountAmount: Value(discountAmount),
              totalAmount: Value(totalAmount),
              paidAmount: Value(paidAmount),
              dueAmount: Value(dueAmount),
              notes: Value(notes),
            ),
          );
    });
  }
}

class SaleItemData {
  final String id;
  final String medicineId;
  final String batchId;
  final int quantity;
  final double saleRate;
  final double mrp;
  final double gstPercent;
  final double discountAmount;

  const SaleItemData({
    required this.id,
    required this.medicineId,
    required this.batchId,
    required this.quantity,
    required this.saleRate,
    required this.mrp,
    required this.gstPercent,
    this.discountAmount = 0.0,
  });
}
