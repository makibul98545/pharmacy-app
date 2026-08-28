import '../repositories/dashboard_repository.dart';
import '../utils/dashboard_date_ranges.dart';

class DashboardController {
  final DashboardRepository repository;

  DashboardController(this.repository);

  Future<DashboardSummary> loadToday() {
    final range = DashboardDateRanges.today(DateTime.now());

    return repository.getSummary(from: range.from, to: range.to);
  }

  Future<DashboardSummary> loadYesterday() {
    final range = DashboardDateRanges.yesterday(DateTime.now());

    return repository.getSummary(from: range.from, to: range.to);
  }

  Future<DashboardSummary> loadThisWeek() {
    final range = DashboardDateRanges.thisWeek(DateTime.now());

    return repository.getSummary(from: range.from, to: range.to);
  }

  Future<DashboardSummary> loadThisMonth() {
    final range = DashboardDateRanges.thisMonth(DateTime.now());

    return repository.getSummary(from: range.from, to: range.to);
  }

  Future<DashboardSummary> loadLastMonth() {
    final range = DashboardDateRanges.lastMonth(DateTime.now());

    return repository.getSummary(from: range.from, to: range.to);
  }

  Future<DashboardSummary> loadCustomRange({
    required DateTime from,
    required DateTime to,
  }) {
    return repository.getSummary(from: from, to: to);
  }
}
