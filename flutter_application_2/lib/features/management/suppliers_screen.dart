import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../domain/models/supplier.dart';
import '../suppliers/supplier_form_screen.dart';
import '../suppliers/supplier_profile_screen.dart';
import '../suppliers/supplier_repository.dart';
import '../suppliers/supplier_statement.dart';
import '../exports/excel_export_service.dart';
import '../receiving/delivery_repository.dart';
import '../company/company_branding.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    required this.repository,
    required this.deliveryRepository,
    required this.onLogout,
    this.brandingService,
    this.recorderNamesProvider,
    super.key,
  });

  final SupplierRepository repository;
  final DeliveryRepository deliveryRepository;
  final VoidCallback onLogout;
  final CompanyBrandingService? brandingService;
  final Future<Map<String, String>> Function()? recorderNamesProvider;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _searchController = TextEditingController();
  SupplierType? _type;
  bool _showInactive = false;

  List<Supplier> get _suppliers {
    return widget.repository.search(_searchController.text).where((supplier) {
      return (_showInactive || supplier.isActive) &&
          (_type == null || supplier.type == _type);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createSupplier() async {
    await Navigator.push<Supplier>(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierFormScreen(repository: widget.repository),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = _suppliers;
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      drawer: _ManagementDrawer(onLogout: widget.onLogout),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSupplier,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add supplier'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Farmer and aggregator profiles',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search by name, ID, phone, or town',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Farmers'),
                selected: _type == SupplierType.farmer,
                onSelected: (selected) => setState(
                  () => _type = selected ? SupplierType.farmer : null,
                ),
              ),
              FilterChip(
                label: const Text('Aggregators'),
                selected: _type == SupplierType.aggregator,
                onSelected: (selected) => setState(
                  () => _type = selected ? SupplierType.aggregator : null,
                ),
              ),
              FilterChip(
                label: const Text('Show inactive'),
                selected: _showInactive,
                onSelected: (selected) =>
                    setState(() => _showInactive = selected),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (suppliers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No suppliers found.'),
              ),
            ),
          ...suppliers.map(
            (supplier) => Card(
              child: ListTile(
                leading: Icon(
                  supplier.type == SupplierType.farmer
                      ? Icons.person_outline
                      : Icons.groups_outlined,
                ),
                title: Text(supplier.name),
                subtitle: Text(
                  '${supplier.id} · ${supplier.town} · ${supplier.isActive ? 'Active' : 'Inactive'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplierProfileScreen(
                        repository: widget.repository,
                        supplier: supplier,
                        brandingService: widget.brandingService,
                        recorderNamesProvider: widget.recorderNamesProvider,
                        statementService: SupplierStatementService(
                          widget.deliveryRepository,
                        ),
                        statementExporter: ExcelExportService(
                          widget.deliveryRepository,
                          companyNameProvider: () =>
                              widget.brandingService?.currentBranding?.name ??
                              'Company',
                          recorderNamesProvider: widget.recorderNamesProvider,
                        ),
                      ),
                    ),
                  );
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagementDrawer extends StatelessWidget {
  const _ManagementDrawer({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 20, 16),
          child: Text('Management App'),
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
