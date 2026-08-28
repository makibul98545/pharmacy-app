import 'package:flutter/material.dart';

import '../controllers/dashboard_controller.dart';
import '../database/app_database.dart';
import '../repositories/dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final AppDatabase _database;
  late final DashboardController _controller;

  DashboardSummary? _summary;

  String _selectedPeriod = 'This Month';

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _database = AppDatabase();
    _controller = DashboardController(DashboardRepository(_database));

    _loadDashboard();
  }

  @override
  void dispose() {
    _database.close();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _loadSelectedPeriod();

      if (!mounted) {
        return;
      }

      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<DashboardSummary> _loadSelectedPeriod() {
    switch (_selectedPeriod) {
      case 'Today':
        return _controller.loadToday();

      case 'Yesterday':
        return _controller.loadYesterday();

      case 'This Week':
        return _controller.loadThisWeek();

      case 'This Month':
        return _controller.loadThisMonth();

      case 'Last Month':
        return _controller.loadLastMonth();

      default:
        return _controller.loadThisMonth();
    }
  }

  Future<void> _selectPeriod(String period) async {
    Navigator.of(context).pop();

    setState(() {
      _selectedPeriod = period;
    });

    await _loadDashboard();
  }

  void _showPeriodSelector() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Period',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              ...[
                'Today',
                'Yesterday',
                'This Week',
                'This Month',
                'Last Month',
              ].map(
                (period) => ListTile(
                  leading: Icon(
                    period == _selectedPeriod
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(period),
                  onTap: () => _selectPeriod(period),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('Custom Range'),
                onTap: _selectCustomRange,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectCustomRange() async {
    Navigator.of(context).pop();

    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 6)),
        end: now,
      ),
    );

    if (picked == null) {
      return;
    }

    final from = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );

    final to = DateTime(picked.end.year, picked.end.month, picked.end.day + 1);

    setState(() {
      _selectedPeriod = 'Custom Range';
    });

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _controller.loadCustomRange(from: from, to: to);

      if (!mounted) {
        return;
      }

      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(summary)),
    );
  }

  Widget _buildBody(DashboardSummary? summary) {
    if (_loading && summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Unable to load dashboard',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (summary == null) {
      return const Center(child: Text('No dashboard data available.'));
    }

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateSelector(),
            const SizedBox(height: 20),
            const Text(
              'Business Overview',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildCards(summary),
            const SizedBox(height: 24),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.calendar_month),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedPeriod,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showPeriodSelector,
              icon: const Icon(Icons.keyboard_arrow_down),
              label: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCards(DashboardSummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1100
            ? 4
            : width >= 700
            ? 3
            : width >= 450
            ? 2
            : 1;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.65,
          children: [
            _DashboardCard(
              title: 'Total Sales',
              value: _money(summary.totalSales),
              icon: Icons.point_of_sale,
            ),
            _DashboardCard(
              title: 'Purchases',
              value: _money(summary.totalPurchases),
              icon: Icons.shopping_cart,
            ),
            _DashboardCard(
              title: 'Customer Due',
              value: _money(summary.customerDue),
              icon: Icons.people,
            ),
            _DashboardCard(
              title: 'Supplier Due',
              value: _money(summary.supplierDue),
              icon: Icons.local_shipping,
            ),
            _DashboardCard(
              title: 'Expenses',
              value: _money(summary.totalExpenses),
              icon: Icons.receipt_long,
            ),
            _DashboardCard(
              title: 'Gross Profit',
              value: _money(summary.grossProfit),
              icon: Icons.trending_up,
            ),
            _DashboardCard(
              title: 'Net Profit',
              value: _money(summary.netProfit),
              icon: Icons.account_balance,
            ),
            _DashboardCard(
              title: 'Current Stock',
              value: summary.currentStock.toString(),
              icon: Icons.inventory_2,
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.point_of_sale),
              label: const Text('New Sale'),
            ),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('New Purchase'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.person_add),
              label: const Text('Customer'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.local_shipping),
              label: const Text('Supplier'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.receipt_long),
              label: const Text('Expense'),
            ),
          ],
        ),
      ],
    );
  }

  String _money(double value) {
    return '₹${value.toStringAsFixed(2)}';
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
