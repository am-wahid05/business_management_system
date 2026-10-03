import 'package:flutter/material.dart';

import '../exports/excel_export_service.dart';
import '../receiving/delivery_repository.dart';
import 'supplier_repository.dart';
import 'supplier_statement.dart';
import 'supplier_statement_screen.dart';

class SupplierStatementsScreen extends StatelessWidget {
  const SupplierStatementsScreen({
    required this.repository,
    required this.deliveryRepository,
    this.companyNameProvider,
    this.recorderNamesProvider,
    super.key,
  });

  final SupplierRepository repository;
  final DeliveryRepository deliveryRepository;
  final String Function()? companyNameProvider;
  final Future<Map<String, String>> Function()? recorderNamesProvider;

  @override
  Widget build(BuildContext context) {
    final statementService = SupplierStatementService(deliveryRepository);
    final exporter = ExcelExportService(
      deliveryRepository,
      companyNameProvider: companyNameProvider,
      recorderNamesProvider: recorderNamesProvider,
    );
    final suppliers = repository.suppliers
        .where((supplier) => supplier.isActive)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier Statements')),
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
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No active suppliers found.'),
              ),
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
