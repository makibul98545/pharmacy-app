import '../database/app_database.dart';

class DashboardSummary {
  final double totalSales;
  final double totalPurchases;
  final double customerDue;
  final double supplierDue;
  final double totalExpenses;
  final int currentStock;
  final double grossProfit;
  final double netProfit;

  const DashboardSummary({
    required this.totalSales,
    required this.totalPurchases,
    required this.customerDue,
    required this.supplierDue,
    required this.totalExpenses,
    required this.currentStock,
    required this.grossProfit,
    required this.netProfit,
  });
}

class DashboardRepository {
  final AppDatabase database;

  DashboardRepository(this.database);

  bool _sameOrAfter(DateTime date, DateTime boundary) {
    return date.millisecondsSinceEpoch >= boundary.millisecondsSinceEpoch;
  }

  bool _before(DateTime date, DateTime? to) {
    if (to == null) {
      return true;
    }

    return date.millisecondsSinceEpoch < to.millisecondsSinceEpoch;
  }

  bool _inRange(DateTime date, DateTime? from, DateTime? to) {
    if (from != null && !_sameOrAfter(date, from)) {
      return false;
    }

    if (to != null && !_before(date, to)) {
      return false;
    }

    return true;
  }

  Future<double> getTotalSales({DateTime? from, DateTime? to}) async {
    final sales = await database.select(database.sales).get();

    double total = 0.0;

    for (final sale in sales) {
      if (_inRange(sale.saleDate, from, to)) {
        total += sale.totalAmount;
      }
    }

    return total;
  }

  Future<double> getTotalPurchases({DateTime? from, DateTime? to}) async {
    final purchases = await database.select(database.purchases).get();

    double total = 0.0;

    for (final purchase in purchases) {
      if (_inRange(purchase.purchaseDate, from, to)) {
        total += purchase.totalAmount;
      }
    }

    return total;
  }

  Future<double> getCustomerDue({DateTime? to}) async {
    final customers = await database.select(database.customers).get();

    double totalDue = 0.0;

    for (final customer in customers) {
      final sales = await database.select(database.sales).get();

      final payments = await database.select(database.customerPayments).get();

      double due = customer.openingBalance;

      for (final sale in sales) {
        if (sale.customerId == customer.id && _before(sale.saleDate, to)) {
          due += sale.dueAmount;
        }
      }

      for (final payment in payments) {
        if (payment.customerId == customer.id &&
            _before(payment.paymentDate, to)) {
          due -= payment.amount;
        }
      }

      totalDue += due;
    }

    return totalDue;
  }

  Future<double> getSupplierDue({DateTime? to}) async {
    final suppliers = await database.select(database.suppliers).get();

    final purchases = await database.select(database.purchases).get();

    final payments = await database.select(database.supplierPayments).get();

    double totalDue = 0.0;

    for (final supplier in suppliers) {
      double due = supplier.openingBalance;

      for (final purchase in purchases) {
        if (purchase.supplierId == supplier.id &&
            _before(purchase.purchaseDate, to)) {
          due += purchase.totalAmount;
        }
      }

      for (final payment in payments) {
        if (payment.supplierId == supplier.id &&
            _before(payment.paymentDate, to)) {
          due -= payment.amount;
        }
      }

      totalDue += due;
    }

    return totalDue;
  }

  Future<double> getTotalExpenses({DateTime? from, DateTime? to}) async {
    final expenses = await database.select(database.expenses).get();

    double total = 0.0;

    for (final expense in expenses) {
      if (_inRange(expense.expenseDate, from, to)) {
        total += expense.amount;
      }
    }

    return total;
  }

  Future<int> getCurrentStock({DateTime? to}) async {
    final movements = await database.select(database.stockMovements).get();

    int stock = 0;

    for (final movement in movements) {
      if (!_before(movement.movementDate, to)) {
        continue;
      }

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

  Future<double> getGrossProfit({DateTime? from, DateTime? to}) async {
    final sales = await database.select(database.sales).get();

    final saleItems = await database.select(database.saleItems).get();

    final batches = await database.select(database.batches).get();

    double revenue = 0.0;
    double cost = 0.0;

    final selectedSaleIds = <String>{};

    // Revenue comes from the Sales table.
    for (final sale in sales) {
      if (_inRange(sale.saleDate, from, to)) {
        selectedSaleIds.add(sale.id);
        revenue += sale.totalAmount;
      }
    }

    // COGS comes from SaleItems and the corresponding batch purchase rate.
    for (final item in saleItems) {
      if (!selectedSaleIds.contains(item.saleId)) {
        continue;
      }

      for (final batch in batches) {
        if (batch.id == item.batchId) {
          cost += item.quantity * batch.purchaseRate;
          break;
        }
      }
    }

    return revenue - cost;
  }

  Future<double> getNetProfit({DateTime? from, DateTime? to}) async {
    final grossProfit = await getGrossProfit(from: from, to: to);

    final expenses = await getTotalExpenses(from: from, to: to);

    return grossProfit - expenses;
  }

  Future<DashboardSummary> getSummary({DateTime? from, DateTime? to}) async {
    final totalSales = await getTotalSales(from: from, to: to);

    final totalPurchases = await getTotalPurchases(from: from, to: to);

    final customerDue = await getCustomerDue(to: to);

    final supplierDue = await getSupplierDue(to: to);

    final totalExpenses = await getTotalExpenses(from: from, to: to);

    final currentStock = await getCurrentStock(to: to);

    final grossProfit = await getGrossProfit(from: from, to: to);

    return DashboardSummary(
      totalSales: totalSales,
      totalPurchases: totalPurchases,
      customerDue: customerDue,
      supplierDue: supplierDue,
      totalExpenses: totalExpenses,
      currentStock: currentStock,
      grossProfit: grossProfit,
      netProfit: grossProfit - totalExpenses,
    );
  }
}
