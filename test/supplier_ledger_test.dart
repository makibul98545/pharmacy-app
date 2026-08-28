import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/supplier_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('supplier due is calculated from purchases and payments', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final supplierRepository = SupplierRepository(database);

    const supplierId = 'supplier-001';

    // Create supplier.
    await supplierRepository.insertSupplier(
      id: supplierId,
      name: 'ABC Pharma Distributors',
    );

    // Create a purchase of ₹10,000.
    await database
        .into(database.purchases)
        .insert(
          PurchasesCompanion.insert(
            id: 'purchase-001',
            supplierId: supplierId,
            purchaseDate: DateTime(2026, 8, 12),
            subtotal: const Value(10_000.0),
            gstAmount: const Value(0.0),
            totalAmount: const Value(10_000.0),
          ),
        );

    // Initial due = ₹10,000.
    var due = await supplierRepository.getDue(supplierId);

    expect(due, 10_000.0);

    // Pay ₹7,000.
    await supplierRepository.recordPayment(
      paymentId: 'supplier-payment-001',
      supplierId: supplierId,
      amount: 7_000.0,
      paymentDate: DateTime(2026, 8, 12),
    );

    due = await supplierRepository.getDue(supplierId);

    // Remaining due = ₹3,000.
    expect(due, 3_000.0);

    // Pay another ₹2,000.
    await supplierRepository.recordPayment(
      paymentId: 'supplier-payment-002',
      supplierId: supplierId,
      amount: 2_000.0,
      paymentDate: DateTime(2026, 8, 12),
    );

    due = await supplierRepository.getDue(supplierId);

    // Remaining due = ₹1,000.
    expect(due, 1_000.0);

    await database.close();
  });
}
