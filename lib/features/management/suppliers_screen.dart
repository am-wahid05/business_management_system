import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_responsive.dart';
import '../../app/app_ui.dart';
import '../auth/active_company_context.dart';
import '../../domain/models/supplier.dart';
import '../suppliers/supplier_form_screen.dart';
import '../suppliers/supplier_profile_screen.dart';
import '../suppliers/supplier_repository.dart';
import '../suppliers/supplier_statement.dart';
import '../exports/excel_export_service.dart';
import '../receiving/delivery_repository.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    required this.repository,
    required this.deliveryRepository,
    required this.onLogout,
    this.activeCompanyContext,
    super.key,
  });

  final SupplierRepository repository;
  final DeliveryRepository deliveryRepository;
  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _searchController = TextEditingController();
  SupplierType? _type;
  bool _showInactive = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.activeCompanyContext?.addListener(_companyChanged);
    widget.repository.addListener(_repositoryChanged);
    _loadSuppliers();
  }

  void _companyChanged() => _loadSuppliers();

  void _repositoryChanged() {
    if (mounted) setState(() {});
  }

  void _loadSuppliers() {
    setState(() => _loading = true);
    widget.repository
        .initialize()
        .then((_) {
          if (mounted) setState(() => _loading = false);
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  List<Supplier> get _suppliers {
    return widget.repository.search(_searchController.text).where((supplier) {
      return (_showInactive || supplier.isActive) &&
          (_type == null || supplier.type == _type);
    }).toList();
  }

  @override
  void dispose() {
    widget.activeCompanyContext?.removeListener(_companyChanged);
    widget.repository.removeListener(_repositoryChanged);
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
      drawer: adminDrawerFor(
        context,
        onLogout: widget.onLogout,
        activeCompanyContext: widget.activeCompanyContext,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSupplier,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add supplier'),
      ),
      body: AppResponsive(
        maxWidth: AppBreakpoints.contentMaxWidth,
        centre: false,
        builder: (context, size) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const AppPageHeader(
                title: 'Suppliers',
                subtitle: 'Farmer and aggregator profiles',
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
              if (_loading)
                const AppLoadingList(rows: 6)
              else if (suppliers.isEmpty)
                AppEmptyState(
                  title: 'No suppliers found',
                  message:
                      'Try a different search or add a new supplier profile.',
                  icon: Icons.people_outline,
                  action: OutlinedButton.icon(
                    onPressed: _createSupplier,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add supplier'),
                  ),
                ),
              if (!_loading)
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
                              activeCompanyContext: widget.activeCompanyContext,
                              statementService: SupplierStatementService(
                                widget.deliveryRepository,
                              ),
                              statementExporter: ExcelExportService(
                                widget.deliveryRepository,
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
          );
        },
      ),
    );
  }
}
