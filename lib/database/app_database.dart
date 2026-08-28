import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Medicines extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 255)();

  TextColumn get hsnCode => text().nullable()();

  RealColumn get gstPercent => real().withDefault(const Constant(0.0))();

  TextColumn get scheduleType => text().nullable()();

  IntColumn get minimumStock => integer().withDefault(const Constant(0))();

  IntColumn get suggestedOrderQty => integer().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Suppliers extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 255)();

  TextColumn get phone => text().nullable()();

  TextColumn get address => text().nullable()();

  TextColumn get gstin => text().nullable()();

  RealColumn get openingBalance => real().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Batch')
class Batches extends Table {
  TextColumn get id => text()();

  TextColumn get medicineId => text()();

  TextColumn get supplierId => text().nullable()();

  TextColumn get batchNo => text().withLength(min: 1, max: 100)();

  TextColumn get hsnCode => text().nullable()();

  DateTimeColumn get expiryDate => dateTime()();

  RealColumn get purchaseRate => real().withDefault(const Constant(0))();

  RealColumn get mrp => real().withDefault(const Constant(0.0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Purchase')
class Purchases extends Table {
  TextColumn get id => text()();

  TextColumn get invoiceNo => text().nullable()();

  TextColumn get supplierId => text()();

  DateTimeColumn get purchaseDate => dateTime()();

  RealColumn get subtotal => real().withDefault(const Constant(0.0))();

  RealColumn get gstAmount => real().withDefault(const Constant(0.0))();

  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PurchaseItem')
class PurchaseItems extends Table {
  TextColumn get id => text()();

  TextColumn get purchaseId => text()();

  TextColumn get medicineId => text()();

  TextColumn get batchId => text()();

  IntColumn get quantity => integer()();

  RealColumn get purchaseRate => real().withDefault(const Constant(0.0))();

  RealColumn get mrp => real().withDefault(const Constant(0.0))();

  RealColumn get gstPercent => real().withDefault(const Constant(0.0))();

  RealColumn get gstAmount => real().withDefault(const Constant(0.0))();

  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StockMovement')
class StockMovements extends Table {
  TextColumn get id => text()();

  TextColumn get medicineId => text()();

  TextColumn get batchId => text()();

  TextColumn get movementType => text()();

  IntColumn get quantity => integer()();

  TextColumn get referenceId => text().nullable()();

  DateTimeColumn get movementDate => dateTime()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Sale')
class Sales extends Table {
  TextColumn get id => text()();

  TextColumn get invoiceNo => text().nullable()();

  TextColumn get customerId => text().nullable()();

  DateTimeColumn get saleDate => dateTime()();

  RealColumn get subtotal => real().withDefault(const Constant(0.0))();

  RealColumn get gstAmount => real().withDefault(const Constant(0.0))();

  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();

  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();

  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();

  RealColumn get dueAmount => real().withDefault(const Constant(0.0))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SaleItem')
class SaleItems extends Table {
  TextColumn get id => text()();

  TextColumn get saleId => text()();

  TextColumn get medicineId => text()();

  TextColumn get batchId => text()();

  IntColumn get quantity => integer()();

  RealColumn get saleRate => real().withDefault(const Constant(0.0))();

  RealColumn get mrp => real().withDefault(const Constant(0.0))();

  RealColumn get gstPercent => real().withDefault(const Constant(0.0))();

  RealColumn get gstAmount => real().withDefault(const Constant(0.0))();

  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();

  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Customer')
class Customers extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 255)();

  TextColumn get phone => text().nullable()();

  TextColumn get address => text().nullable()();

  TextColumn get gstin => text().nullable()();

  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CustomerPayment')
class CustomerPayments extends Table {
  TextColumn get id => text()();

  TextColumn get customerId => text()();

  RealColumn get amount => real().withDefault(const Constant(0.0))();

  DateTimeColumn get paymentDate => dateTime()();

  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();

  TextColumn get referenceNo => text().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SupplierPayment')
class SupplierPayments extends Table {
  TextColumn get id => text()();

  TextColumn get supplierId => text()();

  RealColumn get amount => real().withDefault(const Constant(0.0))();

  DateTimeColumn get paymentDate => dateTime()();

  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();

  TextColumn get referenceNo => text().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Expense')
class Expenses extends Table {
  TextColumn get id => text()();

  TextColumn get category => text().withLength(min: 1, max: 100)();

  TextColumn get particulars => text().nullable()();

  RealColumn get amount => real().withDefault(const Constant(0.0))();

  DateTimeColumn get expenseDate => dateTime()();

  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();

  TextColumn get referenceNo => text().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Medicines,
    Suppliers,
    Batches,
    Purchases,
    PurchaseItems,
    StockMovements,
    Sales,
    SaleItems,
    Customers,
    CustomerPayments,
    SupplierPayments,
    Expenses,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);
  @override
  int get schemaVersion => 2;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();

    final file = File('${directory.path}/mm_lifecare_inventory.sqlite');

    return NativeDatabase.createInBackground(file);
  });
}
