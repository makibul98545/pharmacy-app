import 'package:drift/drift.dart';

import '../database/app_database.dart';

class CustomerRepository {
  final AppDatabase database;

  CustomerRepository(this.database);

  Future<List<Customer>> getAll() {
    return database.select(database.customers).get();
  }

  Future<Customer?> getById(String id) {
    return (database.select(
      database.customers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertCustomer({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? gstin,
    double openingBalance = 0.0,
  }) async {
    await database
        .into(database.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            name: name,
            phone: Value(phone),
            address: Value(address),
            gstin: Value(gstin),
            openingBalance: Value(openingBalance),
          ),
        );
  }

  Future<void> recordPayment({
    required String paymentId,
    required String customerId,
    required double amount,
    required DateTime paymentDate,
    String paymentMethod = 'CASH',
    String? referenceNo,
    String? notes,
  }) async {
    await database
        .into(database.customerPayments)
        .insert(
          CustomerPaymentsCompanion.insert(
            id: paymentId,
            customerId: customerId,
            amount: Value(amount),
            paymentDate: paymentDate,
            paymentMethod: Value(paymentMethod),
            referenceNo: Value(referenceNo),
            notes: Value(notes),
          ),
        );
  }

  Future<double> getDue(String customerId) async {
    final customer = await getById(customerId);

    if (customer == null) {
      throw StateError('Customer not found: $customerId');
    }

    final sales = await (database.select(
      database.sales,
    )..where((tbl) => tbl.customerId.equals(customerId))).get();

    final payments = await (database.select(
      database.customerPayments,
    )..where((tbl) => tbl.customerId.equals(customerId))).get();

    double due = customer.openingBalance;

    for (final sale in sales) {
      due += sale.dueAmount;
    }

    for (final payment in payments) {
      due -= payment.amount;
    }

    return due;
  }
}
