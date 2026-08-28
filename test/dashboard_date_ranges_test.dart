import 'package:flutter_test/flutter_test.dart';

import 'package:mm_lifecare_inventory/utils/dashboard_date_ranges.dart';

void main() {
  test('today returns the correct date range', () {
    final now = DateTime(2026, 8, 12, 15, 30);

    final range = DashboardDateRanges.today(now);

    expect(range.from, DateTime(2026, 8, 12));
    expect(range.to, DateTime(2026, 8, 13));
  });

  test('yesterday returns the previous calendar day', () {
    final now = DateTime(2026, 8, 12, 15, 30);

    final range = DashboardDateRanges.yesterday(now);

    expect(range.from, DateTime(2026, 8, 11));
    expect(range.to, DateTime(2026, 8, 12));
  });

  test('this week starts on Monday', () {
    final now = DateTime(2026, 8, 12, 15, 30);

    final range = DashboardDateRanges.thisWeek(now);

    expect(range.from, DateTime(2026, 8, 10));
    expect(range.to, DateTime(2026, 8, 17));
  });

  test('this month returns the current calendar month', () {
    final now = DateTime(2026, 8, 12, 15, 30);

    final range = DashboardDateRanges.thisMonth(now);

    expect(range.from, DateTime(2026, 8, 1));
    expect(range.to, DateTime(2026, 9, 1));
  });

  test('last month returns the previous calendar month', () {
    final now = DateTime(2026, 8, 12, 15, 30);

    final range = DashboardDateRanges.lastMonth(now);

    expect(range.from, DateTime(2026, 7, 1));
    expect(range.to, DateTime(2026, 8, 1));
  });

  test('custom range preserves supplied boundaries', () {
    final from = DateTime(2026, 8, 5);
    final to = DateTime(2026, 8, 12);

    final range = DashboardDateRanges.custom(from: from, to: to);

    expect(range.from, from);
    expect(range.to, to);
  });
}
