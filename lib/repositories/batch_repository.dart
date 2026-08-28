import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart';

class BatchRepository {
  final AppDatabase database;

  BatchRepository(this.database);

  Future<List<Batch>> getAll() async {
    return await database.select(database.batches).get();
  }

  Future<Batch?> getById(String id) async {
    return await (database.select(
      database.batches,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<List<Batch>> getByMedicineId(String medicineId) async {
    return await (database.select(
      database.batches,
    )..where((tbl) => tbl.medicineId.equals(medicineId))).get();
  }

  Future<void> insertBatch({
    required String id,
    required String medicineId,
    String? supplierId,
    required String batchNo,
    String? hsnCode,
    required DateTime expiryDate,
    double purchaseRate = 0.0,
    double mrp = 0.0,
  }) async {
    await database
        .into(database.batches)
        .insert(
          BatchesCompanion.insert(
            id: id,
            medicineId: medicineId,
            supplierId: Value(supplierId),
            batchNo: batchNo,
            hsnCode: Value(hsnCode),
            expiryDate: expiryDate,
            purchaseRate: Value(purchaseRate),
            mrp: Value(mrp),
          ),
        );
  }

  Future<void> deleteBatch(String id) async {
    await (database.delete(
      database.batches,
    )..where((tbl) => tbl.id.equals(id))).go();
  }
}
