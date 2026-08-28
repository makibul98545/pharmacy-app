class SupplierLedgerEntry {
  final DateTime date;
  final String type;
  final String reference;
  final double debit;
  final double credit;
  final double balance;

  const SupplierLedgerEntry({
    required this.date,
    required this.type,
    required this.reference,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}
