import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/batch_repository.dart';
import 'package:mm_lifecare_inventory/repositories/medicine_repository.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('medicine, supplier and batch can be stored and retrieved', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final medicineRepository = MedicineRepository(database);
    final supplierRepository = SupplierRepository(database);
    final batchRepository = BatchRepository(database);

    const medicineId = 'medicine-001';
    const supplierId = 'supplier-001';
    const batchId = 'batch-001';

    await medicineRepository.insertMedicine(
      id: medicineId,
      name: 'Paracetamol 500 mg',
      hsnCode: '3004',
      gstPercent: 5,
      scheduleType: 'OTC',
      minimumStock: 20,
      suggestedOrderQty: 100,
    );

    await supplierRepository.insertSupplier(
      id: supplierId,
      name: 'ABC Pharma Distributors',
      phone: '9876543210',
      gstin: 'TESTGSTIN',
    );

    await batchRepository.insertBatch(
      id: batchId,
      medicineId: medicineId,
      supplierId: supplierId,
      batchNo: 'PCM001',
      hsnCode: '3004',
      expiryDate: DateTime(2028, 12, 31),
      purchaseRate: 10.00,
      mrp: 15.00,
    );

    final medicine = await medicineRepository.getById(medicineId);

    final supplier = await supplierRepository.getById(supplierId);

    final batch = await batchRepository.getById(batchId);

    expect(medicine, isNotNull);
    expect(medicine!.name, 'Paracetamol 500 mg');

    expect(supplier, isNotNull);
    expect(supplier!.name, 'ABC Pharma Distributors');

    expect(batch, isNotNull);
    expect(batch!.batchNo, 'PCM001');
    expect(batch.medicineId, medicineId);
    expect(batch.supplierId, supplierId);
    expect(batch.mrp, 15.00);

    final medicineBatches = await batchRepository.getByMedicineId(medicineId);

    expect(medicineBatches.length, 1);

    await database.close();
  });
}
