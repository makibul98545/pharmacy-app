class DashboardDateRange {
  final DateTime from;
  final DateTime to;

  const DashboardDateRange({required this.from, required this.to});
}

class DashboardDateRanges {
  static DashboardDateRange today(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);

    final end = start.add(const Duration(days: 1));

    return DashboardDateRange(from: start, to: end);
  }

  static DashboardDateRange yesterday(DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);

    final start = todayStart.subtract(const Duration(days: 1));

    return DashboardDateRange(from: start, to: todayStart);
  }

  static DashboardDateRange thisWeek(DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);

    final daysFromMonday = todayStart.weekday - 1;

    final start = todayStart.subtract(Duration(days: daysFromMonday));

    final end = start.add(const Duration(days: 7));

    return DashboardDateRange(from: start, to: end);
  }

  static DashboardDateRange thisMonth(DateTime now) {
    final start = DateTime(now.year, now.month, 1);

    final end = DateTime(now.year, now.month + 1, 1);

    return DashboardDateRange(from: start, to: end);
  }

  static DashboardDateRange lastMonth(DateTime now) {
    final start = DateTime(now.year, now.month - 1, 1);

    final end = DateTime(now.year, now.month, 1);

    return DashboardDateRange(from: start, to: end);
  }

  static DashboardDateRange custom({
    required DateTime from,
    required DateTime to,
  }) {
    return DashboardDateRange(from: from, to: to);
  }
}
