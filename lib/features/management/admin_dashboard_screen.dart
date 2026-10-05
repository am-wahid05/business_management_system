import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_ui.dart';
import '../../app/app_theme.dart';
import '../../app/app_navigation.dart';
import '../../domain/models/delivery.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_repository.dart';
import '../auth/active_company_context.dart';
import '../auth/auth_repository.dart';
import '../company/company_branding.dart';
import '../credits/sms_credit_service.dart';
import '../credits/sms_credits_card.dart';
import '../receiving/delivery_repository.dart';
import 'admin_dashboard_data.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.repository,
    required this.analyticsRepository,
    required this.userName,
    required this.onLogout,
    this.activeCompanyContext,
    this.authRepository,
    this.brandingService,
    this.creditService,
    this.onCompanyChanging,
    this.onCompanyChanged,
    super.key,
  });

  final DeliveryRepository repository;
  final AnalyticsRepository analyticsRepository;
  final String userName;
  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;
  final AuthRepository? authRepository;
  final CompanyBrandingService? brandingService;
  final SmsCreditService? creditService;
  final VoidCallback? onCompanyChanging;
  final Future<void> Function()? onCompanyChanged;

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
    _data = widget.repository
        .forDate(DateTime.now())
        .then(AdminDashboardData.new);
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
        title: widget.activeCompanyContext == null
            ? const Text('Dashboard')
            : CompanyBrandMark(
                context: widget.activeCompanyContext!,
                service: widget.brandingService,
              ),
        actions: [
          if (widget.authRepository != null &&
              widget.activeCompanyContext != null)
            CompanySwitcher(
              authRepository: widget.authRepository!,
              activeCompanyContext: widget.activeCompanyContext!,
              onCompanyChanging: widget.onCompanyChanging,
              onCompanyChanged: widget.onCompanyChanged,
            ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: adminDrawerFor(
        context,
        onLogout: widget.onLogout,
        activeCompanyContext: widget.activeCompanyContext,
        brandingService: widget.brandingService,
      ),
      body: FutureBuilder<AdminDashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _AdminDashboardSkeleton();
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: AppErrorState(
                title: 'Dashboard unavailable',
                message: 'We could not load today\'s receiving summary.',
                onRetry: () => setState(() {
                  _reload();
                  _loadAnalytics();
                }),
              ),
            );
          }
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
              creditService: widget.creditService,
              activeCompanyContext: widget.activeCompanyContext,
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
    this.creditService,
    this.activeCompanyContext,
  });

  final AdminDashboardData data;
  final Future<_DashboardAnalytics> analytics;
  final String userName;

  /// Null when there is no remote backend, in which case the SMS balance card
  /// is omitted rather than shown empty.
  final SmsCreditService? creditService;
  final ActiveCompanyContext? activeCompanyContext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 24, wide ? 28 : 16, 32),
          children: [
            _Greeting(userName: userName),
            const SizedBox(height: 22),
            // A fixed-height wrap rather than GridView.count: a grid's aspect
            // ratio has to be re-tuned at every width, and any width it was not
            // tuned for either clips the value or leaves a dead gap under it.
            LayoutBuilder(
              builder: (context, inner) {
                final columns = inner.maxWidth >= 1080
                    ? 4
                    : inner.maxWidth >= 620
                    ? 2
                    : 1;
                const gap = 14.0;
                final tile = (inner.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: tile,
                      child: AppKpiCard(
                        label: "Today's weight",
                        value: '${data.totalWeight.toStringAsFixed(1)} kg',
                        icon: Icons.scale_outlined,
                      ),
                    ),
                    SizedBox(
                      width: tile,
                      child: AppKpiCard(
                        label: "Today's bags",
                        value: '${data.bagCount}',
                        icon: Icons.inventory_2_outlined,
                        tint: AppTheme.secondary,
                      ),
                    ),
                    SizedBox(
                      width: tile,
                      child: AppKpiCard(
                        label: 'Deliveries today',
                        value: '${data.deliveryCount}',
                        icon: Icons.local_shipping_outlined,
                        tint: AppTheme.info,
                      ),
                    ),
                    SizedBox(
                      width: tile,
                      child: AppKpiCard(
                        label: 'Suppliers today',
                        value: '${data.supplierCount}',
                        icon: Icons.people_outline,
                        tint: AppTheme.success,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (creditService != null) ...[
              SmsCreditsCard(
                service: creditService!,
                companyId: activeCompanyContext?.companyId,
                // An admin or owner manages company billing, so the purchase
                // control is offered to them.
                canTopUp: true,
              ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 24),
            _AnalyticsSection(analytics: analytics),
            const SizedBox(height: 24),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _RecentDeliveries(deliveries: data.deliveries),
                  ),
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
              _RecentDeliveries(deliveries: data.deliveries),
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
        if (snapshot.connectionState != ConnectionState.done) {
          return const Column(
            children: [
              Row(
                children: [
                  Expanded(child: AppKpiSkeleton()),
                  SizedBox(width: 12),
                  Expanded(child: AppKpiSkeleton()),
                  SizedBox(width: 12),
                  Expanded(child: AppKpiSkeleton()),
                ],
              ),
              SizedBox(height: 16),
              AppChartSkeleton(height: 180),
            ],
          );
        }
        if (snapshot.hasError) {
          return const AppErrorState(
            title: 'Analytics unavailable',
            message: 'The dashboard summary could not be calculated right now.',
          );
        }
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

class _AdminDashboardSkeleton extends StatelessWidget {
  const _AdminDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const AppSkeleton(width: 260, height: 28),
        const SizedBox(height: 10),
        const AppSkeleton(width: 360, height: 16),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: columns == 4 ? 1.65 : 1.35,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(4, (_) => const AppKpiSkeleton()),
            );
          },
        ),
        const SizedBox(height: 24),
        const AppChartSkeleton(height: 190),
        const SizedBox(height: 24),
        const AppLoadingList(rows: 4),
      ],
    );
  }
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
                      Navigator.pushNamed(context, AppRoutes.excel),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.spreadsheet),
                  icon: const Icon(Icons.grid_on_outlined),
                  label: const Text('Spreadsheet'),
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
  const _RecentDeliveries({required this.deliveries});

  final List<Delivery> deliveries;

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
          if (deliveries.isEmpty) const Text('No deliveries recorded today.'),
          ...deliveries
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
                          'Bag weights: ${delivery.bagWeights.map((weight) => '${weight.toStringAsFixed(1)} kg').join(', ')}',
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
