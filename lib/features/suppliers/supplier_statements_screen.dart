import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../exports/excel_export_service.dart';
import '../receiving/delivery_repository.dart';
import 'supplier_repository.dart';
import 'supplier_statement.dart';
import 'supplier_statement_screen.dart';

class SupplierStatementsScreen extends StatelessWidget {
  const SupplierStatementsScreen({
    required this.repository,
    required this.deliveryRepository,
    super.key,
  });

  final SupplierRepository repository;
  final DeliveryRepository deliveryRepository;

  @override
  Widget build(BuildContext context) {
    final statementService = SupplierStatementService(deliveryRepository);
    final exporter = ExcelExportService(deliveryRepository);
    final suppliers = repository.suppliers
        .where((supplier) => supplier.isActive)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Statements'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: shellDrawerFor(context),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Choose a supplier',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Statements contain delivery records only. No payment or financial data is included.',
          ),
          const SizedBox(height: 20),
          if (suppliers.isEmpty)
            const AppEmptyState(
              title: 'No active suppliers',
              message:
                  'Add or activate a supplier before creating a statement.',
              icon: Icons.description_outlined,
            )
          else
            ...suppliers.map(
              (supplier) => Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(supplier.name),
                  subtitle: Text('${supplier.type.name} · ${supplier.town}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplierStatementScreen(
                        supplier: supplier,
                        service: statementService,
                        exporter: exporter,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
