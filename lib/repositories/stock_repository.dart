import '../database/app_database.dart';

class StockRepository {
  final AppDatabase database;

  StockRepository(this.database);

  Future<int> getBatchStock(String batchId) async {
    final movements = await (database.select(
      database.stockMovements,
    )..where((tbl) => tbl.batchId.equals(batchId))).get();

    int stock = 0;

    for (final movement in movements) {
      if (movement.movementType == 'PURCHASE' ||
          movement.movementType == 'ADJUSTMENT_IN') {
        stock += movement.quantity;
      } else if (movement.movementType == 'SALE' ||
          movement.movementType == 'ADJUSTMENT_OUT') {
        stock -= movement.quantity;
      }
    }

    return stock;
  }

  Future<int> getMedicineStock(String medicineId) async {
    final movements = await (database.select(
      database.stockMovements,
    )..where((tbl) => tbl.medicineId.equals(medicineId))).get();

    int stock = 0;

    for (final movement in movements) {
      if (movement.movementType == 'PURCHASE' ||
          movement.movementType == 'ADJUSTMENT_IN') {
        stock += movement.quantity;
      } else if (movement.movementType == 'SALE' ||
          movement.movementType == 'ADJUSTMENT_OUT') {
        stock -= movement.quantity;
      }
    }

    return stock;
  }
}
