import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/supplier_ledger_entry.dart';

class SupplierRepository {
  final AppDatabase database;

  SupplierRepository(this.database);

  Future<List<Supplier>> getAll() {
    return database.select(database.suppliers).get();
  }

  Future<Supplier?> getById(String id) {
    return (database.select(
      database.suppliers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<List<SupplierLedgerEntry>> getLedger(String supplierId) async {
    final supplier = await getById(supplierId);

    if (supplier == null) {
      throw StateError('Supplier not found: $supplierId');
    }

    final purchases = await (database.select(
      database.purchases,
    )..where((tbl) => tbl.supplierId.equals(supplierId))).get();

    final payments = await (database.select(
      database.supplierPayments,
    )..where((tbl) => tbl.supplierId.equals(supplierId))).get();

    final entries = <SupplierLedgerEntry>[];

    double balance = supplier.openingBalance;

    // Opening balance
    if (supplier.openingBalance != 0) {
      entries.add(
        SupplierLedgerEntry(
          date: supplier.createdAt,
          type: 'OPENING',
          reference: 'Opening Balance',
          debit: 0,
          credit: supplier.openingBalance,
          balance: balance,
        ),
      );
    }

    // Combine purchases and payments so they can be sorted chronologically.
    final transactions = <Map<String, dynamic>>[
      ...purchases.map(
        (purchase) => {
          'date': purchase.purchaseDate,
          'type': 'PURCHASE',
          'reference': purchase.invoiceNo ?? purchase.id,
          'debit': 0.0,
          'credit': purchase.totalAmount,
        },
      ),
      ...payments.map(
        (payment) => {
          'date': payment.paymentDate,
          'type': 'PAYMENT',
          'reference': payment.referenceNo ?? payment.id,
          'debit': payment.amount,
          'credit': 0.0,
        },
      ),
    ];

    transactions.sort(
      (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
    );

    // Calculate running supplier balance.
    for (final transaction in transactions) {
      final debit = transaction['debit'] as double;
      final credit = transaction['credit'] as double;

      // Purchase increases payable.
      // Payment decreases payable.
      balance += credit - debit;

      entries.add(
        SupplierLedgerEntry(
          date: transaction['date'] as DateTime,
          type: transaction['type'] as String,
          reference: transaction['reference'] as String,
          debit: debit,
          credit: credit,
          balance: balance,
        ),
      );
    }

    return entries;
  }

  Future<void> insertSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? gstin,
    double openingBalance = 0.0,
  }) async {
    await database
        .into(database.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: id,
            name: name,
            phone: Value(phone),
            address: Value(address),
            gstin: Value(gstin),
            openingBalance: Value(openingBalance),
          ),
        );
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? gstin,
    double openingBalance = 0.0,
  }) async {
    await (database.update(
      database.suppliers,
    )..where((tbl) => tbl.id.equals(id))).write(
      SuppliersCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        gstin: Value(gstin),
        openingBalance: Value(openingBalance),
      ),
    );
  }

  Future<void> recordPayment({
    required String paymentId,
    required String supplierId,
    required double amount,
    required DateTime paymentDate,
    String paymentMethod = 'CASH',
    String? referenceNo,
    String? notes,
  }) async {
    await database
        .into(database.supplierPayments)
        .insert(
          SupplierPaymentsCompanion.insert(
            id: paymentId,
            supplierId: supplierId,
            amount: Value(amount),
            paymentDate: paymentDate,
            paymentMethod: Value(paymentMethod),
            referenceNo: Value(referenceNo),
            notes: Value(notes),
          ),
        );
  }

  Future<void> deleteSupplier(String supplierId) async {
    await (database.delete(
      database.suppliers,
    )..where((tbl) => tbl.id.equals(supplierId))).go();
  }

  Future<double> getDue(String supplierId) async {
    final entries = await getLedger(supplierId);

    if (entries.isEmpty) {
      final supplier = await getById(supplierId);

      if (supplier == null) {
        throw StateError('Supplier not found: $supplierId');
      }

      return supplier.openingBalance;
    }

    return entries.last.balance;
  }
}
