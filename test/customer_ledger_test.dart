import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:mm_lifecare_inventory/database/app_database.dart';
import 'package:mm_lifecare_inventory/repositories/customer_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('customer due is calculated from sales and payments', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final customerRepository = CustomerRepository(database);

    const customerId = 'customer-001';

    // Create customer.
    await customerRepository.insertCustomer(
      id: customerId,
      name: 'Test Customer',
    );

    // Create a sale directly for ledger testing.
    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale-001',
            customerId: const Value(customerId),
            saleDate: DateTime(2026, 8, 12),
            subtotal: const Value(1000.0),
            gstAmount: const Value(0.0),
            discountAmount: const Value(0.0),
            totalAmount: const Value(1000.0),
            paidAmount: const Value(0.0),
            dueAmount: const Value(1000.0),
          ),
        );

    // Initial due = ₹1,000.
    var due = await customerRepository.getDue(customerId);

    expect(due, 1000.0);

    // Customer pays ₹600.
    await customerRepository.recordPayment(
      paymentId: 'payment-001',
      customerId: customerId,
      amount: 600.0,
      paymentDate: DateTime(2026, 8, 12),
    );

    due = await customerRepository.getDue(customerId);

    // Remaining due = ₹400.
    expect(due, 400.0);

    // Customer pays another ₹200.
    await customerRepository.recordPayment(
      paymentId: 'payment-002',
      customerId: customerId,
      amount: 200.0,
      paymentDate: DateTime(2026, 8, 12),
    );

    due = await customerRepository.getDue(customerId);

    // Remaining due = ₹200.
    expect(due, 200.0);

    await database.close();
  });
}
