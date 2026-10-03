import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';

/// Neutral label used when the active company does not provide a name.
/// Receipts are customer-facing, so tenant-specific branding must never be
/// hardcoded here.
String _companyLabel(String? companyName) {
  final name = companyName?.trim();
  return (name == null || name.isEmpty) ? 'Company' : name;
}

class ReceiptService {
  const ReceiptService();

  Future<Uint8List> buildPdf(Delivery delivery, {String? companyName}) async {
    final company = _companyLabel(companyName);
    final document = pw.Document();
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(company, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Receiving receipt', style: const pw.TextStyle(fontSize: 14)),
        pw.Divider(),
        pw.Text('Reference: ${delivery.id}'),
        pw.Text('Supplier: ${delivery.supplier.name}'),
        if (delivery.supplier.phone != null) pw.Text('Phone: ${delivery.supplier.phone}'),
        pw.Text('Product: ${delivery.product.name}'),
        pw.Text('Date: ${_date(delivery.recordedAt)}'),
        pw.Text('Time: ${_time(delivery.recordedAt)}'),
        pw.SizedBox(height: 20),
        // A weighing-bridge record has no individual bag weights at all, so it
        // must never print an empty "Bag / Weight" table: that reads as missing
        // data. It prints the stored scale total and bag count instead, which
        // is what was actually measured.
        if (delivery.isBulk) ...[
          pw.Text('Weighing-bridge (bulk) entry', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Measure', 'Value'],
            data: [
              ['Number of bags', '${delivery.numberOfBags}'],
              ['Total weight', '${delivery.totalWeight.toStringAsFixed(1)} kg'],
            ],
          ),
          if (delivery.notes != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('Notes: ${delivery.notes}'),
          ],
        ] else
          pw.TableHelper.fromTextArray(
            headers: const ['Bag', 'Weight'],
            data: [
              for (var index = 0; index < delivery.bagWeights.length; index++)
                ['${index + 1}', '${delivery.bagWeights[index].toStringAsFixed(1)} kg'],
            ],
          ),
        pw.SizedBox(height: 16),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Total bags: ${delivery.numberOfBags}\nTotal weight: ${delivery.totalWeight.toStringAsFixed(1)} kg', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 24),
        pw.Text('Status: ${delivery.status.name}'),
      ]),
    ));
    return document.save();
  }

  Future<void> print(Delivery delivery, {String? companyName}) async {
    final bytes = await buildPdf(delivery, companyName: companyName);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'ALBNC_Receipt_${delivery.id}.pdf');
  }

  Future<void> printSupplierHistory(Supplier supplier, List<Delivery> deliveries, {String? companyName}) async {
    final document = pw.Document();
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Text('${_companyLabel(companyName)} - Supplier History', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      build: (_) => [
        pw.SizedBox(height: 12),
        pw.Text('Supplier: ${supplier.name}'),
        pw.Text('Supplier ID: ${supplier.id}'),
        pw.Text('Type: ${supplier.type.name}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(headers: const ['Date', 'Product', 'Type', 'Bags', 'Weight'], data: deliveries.map((delivery) => [_date(delivery.recordedAt), delivery.product.name, delivery.isBulk ? 'Bulk' : 'Individual', '${delivery.numberOfBags}', '${delivery.totalWeight.toStringAsFixed(1)} kg']).toList()),
        pw.SizedBox(height: 16),
        pw.Text('Total deliveries: ${deliveries.length}'),
        pw.Text('Total bags: ${deliveries.fold<int>(0, (total, delivery) => total + delivery.numberOfBags)}'),
        pw.Text('Total weight: ${deliveries.fold<double>(0, (total, delivery) => total + delivery.totalWeight).toStringAsFixed(1)} kg'),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => document.save(), name: 'ALBNC_Supplier_${supplier.id}.pdf');
  }

  Future<bool> sendByWhatsApp(Delivery delivery, {String? companyName}) async {
    final phone = delivery.supplier.phone?.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone == null || phone.isEmpty) return false;
    final text = Uri.encodeComponent('${_companyLabel(companyName)} receiving receipt\nReference: ${delivery.id}\nSupplier: ${delivery.supplier.name}\nProduct: ${delivery.product.name}\nBags: ${delivery.numberOfBags}\nTotal weight: ${delivery.totalWeight.toStringAsFixed(1)} kg\nDate: ${_date(delivery.recordedAt)}');
    return launchUrl(Uri.parse('https://wa.me/$phone?text=$text'), mode: LaunchMode.externalApplication);
  }

  static String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String _time(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
