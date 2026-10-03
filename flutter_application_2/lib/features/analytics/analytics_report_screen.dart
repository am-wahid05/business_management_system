import 'package:flutter/material.dart';

import '../../app/app_ui.dart';
import '../../domain/models/product.dart';
import '../products/product_repository.dart';
import '../suppliers/supplier_repository.dart';
import 'analytics_models.dart';
import 'analytics_repository.dart';

class AnalyticsReportScreen extends StatefulWidget {
  const AnalyticsReportScreen({
    required this.repository,
    required this.productRepository,
    required this.supplierRepository,
    this.initialTrend = AnalyticsTrend.monthly,
    this.title = 'Reports',
    this.initialFrom,
    this.initialTo,
    super.key,
  });

  final AnalyticsRepository repository;
  final ProductRepository productRepository;
  final SupplierRepository supplierRepository;
  final AnalyticsTrend initialTrend;
  final String title;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<AnalyticsReportScreen> createState() => _AnalyticsReportScreenState();
}

class _AnalyticsReportScreenState extends State<AnalyticsReportScreen> {
  late DateTime _from;
  late DateTime _to;
  late AnalyticsTrend _trend;
  String? _productId;
  String? _supplierId;
  String? _supplierType;
  String _period = 'This year';
  final _townController = TextEditingController();
  final _districtController = TextEditingController();
  final _regionController = TextEditingController();
  late Future<_AnalyticsViewData> _data;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = widget.initialFrom ?? DateTime(today.year, 1, 1);
    _to = widget.initialTo ?? DateTime(today.year, today.month, today.day);
    _trend = widget.initialTrend;
    _load();
  }

  @override
  void dispose() {
    _townController.dispose();
    _districtController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _load() {
    final filters = AnalyticsFilters(
      from: _from,
      to: _to,
      productId: _productId,
      supplierId: _supplierId,
      supplierType: _supplierType,
      town: _townController.text.trim(),
      district: _districtController.text.trim(),
      region: _regionController.text.trim(),
    );
    _data = Future.wait([
      widget.repository.summary(filters),
      widget.repository.productBreakdown(filters),
      widget.repository.supplierBreakdown(filters),
      widget.repository.trend(filters, _trend),
      widget.repository.supplierActivity(filters),
      widget.repository.locationBreakdown(filters),
    ]).then((values) => _AnalyticsViewData(
          summary: values[0] as AnalyticsSummary,
          products: values[1] as List<ProductAnalyticsTotal>,
          suppliers: values[2] as List<SupplierAnalyticsTotal>,
          trend: values[3] as List<AnalyticsTrendTotal>,
          supplierActivity: values[4] as SupplierActivitySummary,
          locations: values[5] as List<LocationAnalyticsTotal>,
        ));
  }

  Future<void> _chooseDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: from ? _from : _to,
    );
    if (selected == null) return;
    final nextFrom = from ? selected : _from;
    final nextTo = from ? _to : selected;
    if (nextTo.isBefore(nextFrom)) {
      _showMessage('The To date must not be before the From date.');
      return;
    }
    setState(() {
      if (from) {
        _from = selected;
      } else {
        _to = selected;
      }
      _load();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime from;
    DateTime to = today;
    switch (period) {
      case 'Today':
        from = today;
        break;
      case 'Yesterday':
        from = today.subtract(const Duration(days: 1));
        to = from;
        break;
      case 'This week':
        from = today.subtract(Duration(days: today.weekday - 1));
        break;
      case 'This month':
        from = DateTime(today.year, today.month);
        break;
      case 'Previous year':
        from = DateTime(today.year - 1);
        to = DateTime(today.year - 1, 12, 31);
        break;
      default:
        from = DateTime(today.year);
    }
    setState(() {
      _period = period;
      _from = from;
      _to = to;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.productRepository.all(activeOnly: false);
    final suppliers = widget.supplierRepository.suppliers;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<Product>>(
        future: products,
        builder: (context, productSnapshot) {
          if (productSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppSectionHeader(title: widget.title, subtitle: '${_formatDate(_from)} - ${_formatDate(_to)}', action: AppStatusPill(label: 'Local data', icon: Icons.storage_outlined, color: Theme.of(context).colorScheme.secondary)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: ['Today', 'Yesterday', 'This week', 'This month', 'This year', 'Previous year'].map((period) => ChoiceChip(label: Text(period), selected: _period == period, onSelected: (_) => _setPeriod(period))).toList()),
              const SizedBox(height: 20),
              Text('Filters', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(onPressed: () => _chooseDate(from: true), icon: const Icon(Icons.calendar_month_outlined), label: Text('From: ${_formatDate(_from)}')),
                  OutlinedButton.icon(onPressed: () => _chooseDate(from: false), icon: const Icon(Icons.calendar_month_outlined), label: Text('To: ${_formatDate(_to)}')),
                  SizedBox(width: 180, child: DropdownButtonFormField<AnalyticsTrend>(initialValue: _trend, decoration: const InputDecoration(labelText: 'Trend'), items: const [DropdownMenuItem(value: AnalyticsTrend.daily, child: Text('Daily')), DropdownMenuItem(value: AnalyticsTrend.weekly, child: Text('Weekly')), DropdownMenuItem(value: AnalyticsTrend.monthly, child: Text('Monthly')), DropdownMenuItem(value: AnalyticsTrend.yearly, child: Text('Yearly'))], onChanged: (value) { if (value != null) setState(() { _trend = value; _load(); }); })),
                  SizedBox(width: 220, child: DropdownButtonFormField<String>(initialValue: _productId, decoration: const InputDecoration(labelText: 'Product'), items: [const DropdownMenuItem<String>(value: null, child: Text('All products')), ...productSnapshot.data!.map((product) => DropdownMenuItem(value: product.id, child: Text(product.name)))], onChanged: (value) => setState(() { _productId = value; _load(); }))),
                  SizedBox(width: 240, child: DropdownButtonFormField<String>(initialValue: _supplierId, decoration: const InputDecoration(labelText: 'Supplier'), items: [const DropdownMenuItem<String>(value: null, child: Text('All suppliers')), ...suppliers.map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name)))], onChanged: (value) => setState(() { _supplierId = value; _load(); }))),
                  SizedBox(width: 180, child: DropdownButtonFormField<String>(initialValue: _supplierType, decoration: const InputDecoration(labelText: 'Type'), items: const [DropdownMenuItem<String>(value: null, child: Text('All types')), DropdownMenuItem(value: 'farmer', child: Text('Farmers')), DropdownMenuItem(value: 'aggregator', child: Text('Aggregators'))], onChanged: (value) => setState(() { _supplierType = value; _load(); }))),
                  SizedBox(width: 180, child: TextField(controller: _townController, decoration: const InputDecoration(labelText: 'Town'), onSubmitted: (_) => setState(_load))),
                  SizedBox(width: 180, child: TextField(controller: _districtController, decoration: const InputDecoration(labelText: 'District'), onSubmitted: (_) => setState(_load))),
                  SizedBox(width: 180, child: TextField(controller: _regionController, decoration: const InputDecoration(labelText: 'Region'), onSubmitted: (_) => setState(_load))),
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => setState(_load), icon: const Icon(Icons.filter_alt_outlined), label: const Text('Apply filters'))),
              const SizedBox(height: 24),
              FutureBuilder<_AnalyticsViewData>(future: _data, builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
                if (snapshot.hasError) return Text('Could not generate report: ${snapshot.error}');
                return _ReportContent(data: snapshot.data!);
              }),
            ],
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _AnalyticsViewData {
  const _AnalyticsViewData({required this.summary, required this.products, required this.suppliers, required this.trend, required this.supplierActivity, required this.locations});

  final AnalyticsSummary summary;
  final List<ProductAnalyticsTotal> products;
  final List<SupplierAnalyticsTotal> suppliers;
  final List<AnalyticsTrendTotal> trend;
  final SupplierActivitySummary supplierActivity;
  final List<LocationAnalyticsTotal> locations;
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({required this.data});

  final _AnalyticsViewData data;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) => GridView.count(crossAxisCount: constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 560 ? 3 : 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: [
        AppKpiCard(label: 'Total weight', value: '${summary.totalWeight.toStringAsFixed(1)} kg', icon: Icons.scale_outlined),
        AppKpiCard(label: 'Total bags', value: '${summary.totalBags}', icon: Icons.inventory_2_outlined, tint: const Color(0xFFB56A20)),
        AppKpiCard(label: 'Deliveries', value: '${summary.deliveryCount}', icon: Icons.local_shipping_outlined, tint: const Color(0xFF2B6CB0)),
        AppKpiCard(label: 'Unique suppliers', value: '${summary.uniqueSuppliers}', icon: Icons.people_outline, tint: const Color(0xFF7A55A8)),
        AppKpiCard(label: 'Farmers', value: '${summary.uniqueFarmers}', icon: Icons.agriculture_outlined),
        AppKpiCard(label: 'Aggregators', value: '${summary.uniqueAggregators}', icon: Icons.hub_outlined),
        AppKpiCard(label: 'Active suppliers', value: '${summary.activeSuppliers}', icon: Icons.verified_user_outlined),
        AppKpiCard(label: 'Avg weight/delivery', value: '${summary.averageWeightPerDelivery.toStringAsFixed(1)} kg', icon: Icons.speed_outlined),
        AppKpiCard(label: 'Avg weight/bag', value: '${summary.averageWeightPerBag.toStringAsFixed(1)} kg', icon: Icons.monitor_weight_outlined),
        AppKpiCard(label: 'Avg bags/delivery', value: summary.averageBagsPerDelivery.toStringAsFixed(1), icon: Icons.view_module_outlined),
      ])),
      const SizedBox(height: 28),
      AppSectionHeader(title: 'Products', subtitle: 'Receiving performance by commodity'),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: AppBarChart(items: data.products.map((item) => AppChartItem(item.productName, item.totalWeight)).toList()))),
      const SizedBox(height: 20),
      if (data.products.isEmpty) const Text('No data available for this period.') else ...data.products.map((item) => Card(child: ExpansionTile(title: Text(item.productName), subtitle: Text('${item.deliveryCount} deliveries · ${item.totalBags} bags'), trailing: Text('${item.totalWeight.toStringAsFixed(1)} kg'), children: [ListTile(title: const Text('Unique suppliers'), trailing: Text('${item.uniqueSuppliers}')), ListTile(title: const Text('Average weight per bag'), trailing: Text('${item.averageWeightPerBag.toStringAsFixed(1)} kg')), ListTile(title: const Text('Average weight per delivery'), trailing: Text('${item.averageWeightPerDelivery.toStringAsFixed(1)} kg'))]))),
      const SizedBox(height: 28),
      AppSectionHeader(title: 'Suppliers', subtitle: 'Neutral activity ranking by total weight'),
      const SizedBox(height: 8),
      if (data.suppliers.isEmpty) const Text('No data available for this period.') else ...data.suppliers.take(50).map((item) => Card(child: ListTile(title: Text(item.supplierName), subtitle: Text('${item.supplierType} · ${item.deliveryCount} deliveries · ${item.totalBags} bags'), trailing: Text('${item.totalWeight.toStringAsFixed(1)} kg')))),
      const SizedBox(height: 16),
      Text('New versus returning suppliers', style: Theme.of(context).textTheme.titleMedium),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('New suppliers'), trailing: Text('${data.supplierActivity.newSuppliers}')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Returning suppliers'), trailing: Text('${data.supplierActivity.returningSuppliers}')),
      const SizedBox(height: 28),
      AppSectionHeader(title: 'Locations', subtitle: 'Recorded supplier locations only'),
      const SizedBox(height: 8),
      if (data.locations.isEmpty) const Text('No location data available for this period.') else ...data.locations.take(50).map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item.location), subtitle: Text('${item.supplierCount} suppliers · ${item.deliveryCount} deliveries · ${item.totalBags} bags'), trailing: Text('${item.totalWeight.toStringAsFixed(1)} kg'))),
      const SizedBox(height: 28),
      AppSectionHeader(title: 'Trends', subtitle: 'Choose daily, weekly, monthly, or yearly grouping above'),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: AppBarChart(items: data.trend.map((item) => AppChartItem(item.period, item.totalWeight)).toList()))),
      if (data.trend.isNotEmpty) ...data.trend.map((item) => ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(item.period), subtitle: Text('${item.deliveryCount} deliveries · ${item.totalBags} bags'), trailing: Text('${item.totalWeight.toStringAsFixed(1)} kg'))),
    ]);
  }
}

