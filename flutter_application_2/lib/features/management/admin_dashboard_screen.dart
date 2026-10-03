import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_ui.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_repository.dart';
import '../receiving/delivery_repository.dart';
import 'admin_dashboard_data.dart';
import '../auth/active_company_context.dart';
import '../auth/auth_repository.dart';
import '../company/company_branding.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.repository,
    required this.analyticsRepository,
    required this.userName,
    required this.onLogout,
    required this.activeCompanyContext,
    required this.authRepository,
    this.onCompanyChanging,
    this.onCompanyChanged,
    this.brandingService,
    super.key,
  });

  final DeliveryRepository repository;
  final AnalyticsRepository analyticsRepository;
  final String userName;
  final VoidCallback onLogout;
  final ActiveCompanyContext activeCompanyContext;
  final AuthRepository authRepository;
  final VoidCallback? onCompanyChanging;
  final Future<void> Function()? onCompanyChanged;
  final CompanyBrandingService? brandingService;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<AdminDashboardData> _data;
  late Future<_DashboardAnalytics> _analytics;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadAnalytics();
  }

  void _reload() {
    _data = () async {
      final deliveries = await widget.repository.forDate(DateTime.now());
      Map<String, String> names = const {};
      try {
        final users = await widget.authRepository.allUsers();
        names = {for (final user in users) user.id: user.displayName};
      } catch (_) {
        // Keep the business records visible if profile-name lookup is offline.
      }
      return AdminDashboardData(deliveries, recorderNames: names);
    }();
  }

  void _loadAnalytics() {
    final today = DateTime.now();
    final filters = AnalyticsFilters(
      from: DateTime(today.year, 1, 1),
      to: today,
    );
    _analytics =
        Future.wait([
          widget.analyticsRepository.summary(filters),
          widget.analyticsRepository.productBreakdown(filters),
          widget.analyticsRepository.trend(filters, AnalyticsTrend.monthly),
        ]).then(
          (values) => _DashboardAnalytics(
            summary: values[0] as AnalyticsSummary,
            products: values[1] as List<ProductAnalyticsTotal>,
            trend: values[2] as List<AnalyticsTrendTotal>,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          CompanySwitcher(
            authRepository: widget.authRepository,
            activeCompanyContext: widget.activeCompanyContext,
            onCompanyChanging: widget.onCompanyChanging,
            onCompanyChanged: widget.onCompanyChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: AppStatusPill(
              label: 'Local data',
              icon: Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ],
      ),
      drawer: _AdminDrawer(
        onLogout: widget.onLogout,
        activeCompanyContext: widget.activeCompanyContext,
        brandingService: widget.brandingService,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.assistant),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Assistant'),
      ),
      body: FutureBuilder<AdminDashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(
              child: Text('Could not load dashboard: ${snapshot.error}'),
            );
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _reload();
                _loadAnalytics();
              });
            },
            child: _DashboardBody(
              data: snapshot.data!,
              analytics: _analytics,
              userName: widget.userName,
            ),
          );
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.analytics,
    required this.userName,
  });

  final AdminDashboardData data;
  final Future<_DashboardAnalytics> analytics;
  final String userName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          children: [
            _Greeting(userName: userName),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: wide ? 4 : 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: wide ? 1.65 : 1.35,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                AppKpiCard(
                  label: 'Total weight',
                  value: '${data.totalWeight.toStringAsFixed(1)} kg',
                  icon: Icons.scale_outlined,
                ),
                AppKpiCard(
                  label: 'Total bags',
                  value: '${data.bagCount}',
                  icon: Icons.inventory_2_outlined,
                  tint: const Color(0xFFB56A20),
                ),
                AppKpiCard(
                  label: 'Deliveries',
                  value: '${data.deliveryCount}',
                  icon: Icons.local_shipping_outlined,
                  tint: const Color(0xFF2B6CB0),
                ),
                AppKpiCard(
                  label: 'Suppliers',
                  value: '${data.supplierCount}',
                  icon: Icons.people_outline,
                  tint: const Color(0xFF7A55A8),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _AnalyticsSection(analytics: analytics),
            const SizedBox(height: 24),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _RecentDeliveries(data: data)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: [
                        _ProductBreakdown(data: data),
                        const SizedBox(height: 16),
                        _SyncPanel(data: data),
                        const SizedBox(height: 16),
                        const _QuickActions(),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              _RecentDeliveries(data: data),
              const SizedBox(height: 16),
              _ProductBreakdown(data: data),
              const SizedBox(height: 16),
              _SyncPanel(data: data),
              const SizedBox(height: 16),
              const _QuickActions(),
            ],
          ],
        );
      },
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, $userName',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              const Text("Here's what's happening with your business today."),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.reports),
          icon: const Icon(Icons.assessment_outlined),
          label: const Text('Daily report'),
        ),
      ],
    );
  }
}

class _DashboardAnalytics {
  const _DashboardAnalytics({
    required this.summary,
    required this.products,
    required this.trend,
  });

  final AnalyticsSummary summary;
  final List<ProductAnalyticsTotal> products;
  final List<AnalyticsTrendTotal> trend;
}

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection({required this.analytics});

  final Future<_DashboardAnalytics> analytics;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardAnalytics>(
      future: analytics,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const LinearProgressIndicator();
        if (snapshot.hasError)
          return Text('Could not load analytics: ${snapshot.error}');
        final data = snapshot.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionHeader(
                  title: 'Analytics overview',
                  subtitle: 'Year-to-date receiving activity',
                  action: FilledButton.icon(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.analytics),
                    icon: const Icon(Icons.insights_outlined),
                    label: const Text('View analytics'),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _AnalyticsMetric(
                      label: 'Total weight',
                      value:
                          '${data.summary.totalWeight.toStringAsFixed(1)} kg',
                    ),
                    _AnalyticsMetric(
                      label: 'Total bags',
                      value: '${data.summary.totalBags}',
                    ),
                    _AnalyticsMetric(
                      label: 'Deliveries',
                      value: '${data.summary.deliveryCount}',
                    ),
                    _AnalyticsMetric(
                      label: 'Suppliers',
                      value: '${data.summary.uniqueSuppliers}',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Weight by product',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                AppBarChart(
                  items: data.products
                      .take(5)
                      .map(
                        (product) => AppChartItem(
                          product.productName,
                          product.totalWeight,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Recent monthly trend',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (data.trend.isEmpty)
                  const AppEmptyState(
                    title: 'No trend data',
                    message: 'Receiving activity will appear here when records exist.',
                  )
                else
                  ...data.trend
                      .take(6)
                      .map(
                        (period) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(period.period),
                          subtitle: Text(
                            '${period.deliveryCount} deliveries · ${period.totalBags} bags',
                          ),
                          trailing: Text(
                            '${period.totalWeight.toStringAsFixed(1)} kg',
                          ),
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionHeader(
              title: 'Quick actions',
              subtitle: 'Common management tasks',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.suppliers),
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Suppliers'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.deliveries),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Deliveries'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.excel),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.analytics),
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('Analytics'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductBreakdown extends StatelessWidget {
  const _ProductBreakdown({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Product breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (data.productTotals.isEmpty) const Text('No deliveries today.'),
          ...data.productTotals.values.map(
            (total) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(total.name),
              subtitle: Text('${total.bags} bags'),
              trailing: Text(
                '${total.weight.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Synchronization status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (data.synchronizationTotals.isEmpty)
            const Text('No delivery records today.'),
          ...data.synchronizationTotals.entries.map(
            (entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_statusIcon(entry.key)),
              title: Text(_statusLabel(entry.key)),
              trailing: Text('${entry.value}'),
            ),
          ),
        ],
      ),
    ),
  );

  static IconData _statusIcon(String status) => status == 'synchronized'
      ? Icons.cloud_done_outlined
      : status == 'failed'
      ? Icons.cloud_off_outlined
      : Icons.cloud_upload_outlined;
  static String _statusLabel(String status) => status == 'synchronized'
      ? 'Synchronized'
      : status == 'failed'
      ? 'Failed'
      : 'Pending';
}

class _RecentDeliveries extends StatelessWidget {
  const _RecentDeliveries({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent deliveries',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (data.deliveries.isEmpty)
            const Text('No deliveries recorded today.'),
          ...data.deliveries
              .take(8)
              .map(
                (delivery) => ExpansionTile(
                  title: Text(delivery.supplier.name),
                  subtitle: Text(
                    '${delivery.product.name} · ${delivery.numberOfBags} bags · ${delivery.recordedAt.hour.toString().padLeft(2, '0')}:${delivery.recordedAt.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: Text(
                    '${delivery.totalWeight.toStringAsFixed(1)} kg',
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Recorded by: ${data.recorderName(delivery.recordedByUserId)}\nBag weights: ${delivery.bagWeights.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value.toStringAsFixed(1)} kg (${data.recorderName(delivery.recorderForBag(entry.key))})').join(', ')}',
                        ),
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

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({
    required this.onLogout,
    required this.activeCompanyContext,
    this.brandingService,
  });

  final VoidCallback onLogout;
  final ActiveCompanyContext activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 20, 18),
          child: CompanyBrandMark(
            context: activeCompanyContext,
            service: brandingService,
            nameStyle: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        _item(
          context,
          'Dashboard',
          Icons.dashboard_outlined,
          AppRoutes.adminDashboard,
        ),
        _item(context, 'Suppliers', Icons.people_outline, AppRoutes.suppliers),
        _item(
          context,
          'Deliveries',
          Icons.local_shipping_outlined,
          AppRoutes.deliveries,
        ),
        const _ReportsNavigationItem(),
        _item(
          context,
          'Analytics',
          Icons.insights_outlined,
          AppRoutes.analytics,
        ),
        _item(
          context,
          'Statements',
          Icons.receipt_long_outlined,
          AppRoutes.statements,
        ),
        _item(
          context,
          'Products',
          Icons.inventory_2_outlined,
          AppRoutes.products,
        ),
        _item(context, 'Excel', Icons.table_chart_outlined, AppRoutes.excel),
        _item(
          context,
          'Users',
          Icons.manage_accounts_outlined,
          AppRoutes.users,
        ),
        _item(context, 'Settings', Icons.settings_outlined, AppRoutes.settings),
        _item(
          context,
          'Business Assistant',
          Icons.auto_awesome,
          AppRoutes.assistant,
        ),
        _item(
          context,
          'Log out',
          Icons.logout,
          AppRoutes.login,
          onLogout: onLogout,
        ),
      ],
    );
  }

  static Widget _item(
    BuildContext context,
    String label,
    IconData icon,
    String route, {
    VoidCallback? onLogout,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    onTap: () {
      final navigator = Navigator.of(context);
      navigator.pop();
      if (route == AppRoutes.login) {
        onLogout?.call();
        navigator.pushReplacementNamed(route);
      } else {
        navigator.pushNamed(route);
      }
    },
  );
}

class _ReportsNavigationItem extends StatelessWidget {
  const _ReportsNavigationItem();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: const Icon(Icons.assessment_outlined),
        title: const Text('Reports'),
        subtitle: const Text('Daily, monthly, yearly'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.only(left: 20, right: 8, bottom: 4),
        children: [
          _reportItem(
            context,
            'Daily Report',
            Icons.today_outlined,
            AppRoutes.reports,
          ),
          _reportItem(
            context,
            'Monthly Report',
            Icons.calendar_view_month_outlined,
            AppRoutes.monthlyReports,
          ),
          _reportItem(
            context,
            'Yearly Report',
            Icons.calendar_today_outlined,
            AppRoutes.yearlyReports,
          ),
        ],
      ),
    );
  }

  static Widget _reportItem(
    BuildContext context,
    String label,
    IconData icon,
    String route,
  ) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.pushNamed(route);
      },
    );
  }
}
