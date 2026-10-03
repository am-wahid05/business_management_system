import 'package:flutter/material.dart';

import '../reports/daily_report.dart';
import '../reports/daily_report_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({required this.repository, super.key});

  final DailyReportRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _selectedDate;
  late Future<DailyReport> _report;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadReport();
  }

  void _loadReport() {
    _report = widget.repository.forDate(_selectedDate);
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: _selectedDate);
    if (date != null) setState(() { _selectedDate = date; _loadReport(); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily / Day-Break Report'), actions: [IconButton(tooltip: 'Choose date', onPressed: _chooseDate, icon: const Icon(Icons.calendar_month_outlined))]),
      body: FutureBuilder<DailyReport>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Could not generate report: ${snapshot.error}'));
          return _ReportBody(report: snapshot.data!);
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Day-break report', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(_formatDate(report.date), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _SummaryCard(label: 'Suppliers', value: '${report.supplierCount}'),
          _SummaryCard(label: 'Deliveries', value: '${report.deliveryCount}'),
          _SummaryCard(label: 'Bags', value: '${report.totalBags}'),
          _SummaryCard(label: 'Total weight', value: '${report.totalWeight.toStringAsFixed(1)} kg'),
        ]),
        const SizedBox(height: 28),
        Text('Receiving detail', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (report.deliveries.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No delivery records for this date.')))
        else
          ...report.deliveries.map((delivery) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(delivery.supplier.name, style: Theme.of(context).textTheme.titleMedium)), Text(DailyReport.supplierTypeLabel(delivery.supplier.type))]),
                const SizedBox(height: 8),
                Text('${delivery.product.name} · ${delivery.numberOfBags} bags · ${delivery.totalWeight.toStringAsFixed(1)} kg'),
              ])))),
        const SizedBox(height: 28),
        Text('Product totals', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...report.productTotals.map((total) => Card(child: ListTile(title: Text(total.productName.toUpperCase()), subtitle: Text('${total.bagCount} bags'), trailing: Text('${total.totalWeight.toStringAsFixed(1)} kg', style: Theme.of(context).textTheme.titleMedium)))),
      ],
    );
  }

  static String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const SizedBox(height: 4), Text(value, style: Theme.of(context).textTheme.titleLarge)])));
}
