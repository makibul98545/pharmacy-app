import 'package:drift/drift.dart';

import '../database/app_database.dart';

class MedicineRepository {
  final AppDatabase database;

  MedicineRepository(this.database);

  Future<List<Medicine>> getAll() {
    return database.select(database.medicines).get();
  }

  Future<Medicine?> getById(String id) {
    return (database.select(
      database.medicines,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertMedicine({
    required String id,
    required String name,
    String? hsnCode,
    double gstPercent = 0,
    String? scheduleType,
    int minimumStock = 0,
    int suggestedOrderQty = 0,
  }) async {
    await database
        .into(database.medicines)
        .insert(
          MedicinesCompanion.insert(
            id: id,
            name: name,
            hsnCode: Value(hsnCode),
            gstPercent: Value(gstPercent),
            scheduleType: Value(scheduleType),
            minimumStock: Value(minimumStock),
            suggestedOrderQty: Value(suggestedOrderQty),
          ),
        );
  }

  Future<void> updateMedicine({
    required String id,
    required String name,
    String? hsnCode,
    double gstPercent = 0,
    String? scheduleType,
    int minimumStock = 0,
    int suggestedOrderQty = 0,
    bool isActive = true,
  }) async {
    await (database.update(
      database.medicines,
    )..where((tbl) => tbl.id.equals(id))).write(
      MedicinesCompanion(
        name: Value(name),
        hsnCode: Value(hsnCode),
        gstPercent: Value(gstPercent),
        scheduleType: Value(scheduleType),
        minimumStock: Value(minimumStock),
        suggestedOrderQty: Value(suggestedOrderQty),
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteMedicine(String id) {
    return (database.delete(
      database.medicines,
    )..where((tbl) => tbl.id.equals(id))).go();
  }
}
