import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';

class ReceiptService {
  const ReceiptService();

  Future<Uint8List> buildPdf(
    Delivery delivery, {
    String companyName = 'Company',
    Uint8List? logoBytes,
    Map<String, String> recorderNames = const {},
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoBytes != null) ...[
                  pw.SizedBox(
                    width: 48,
                    height: 48,
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Receiving receipt',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.Divider(),
            pw.Text('Reference: ${delivery.id}'),
            pw.Text('Supplier: ${delivery.supplier.name}'),
            if (delivery.supplier.phone != null)
              pw.Text('Phone: ${delivery.supplier.phone}'),
            pw.Text('Product: ${delivery.product.name}'),
            pw.Text('Date: ${_date(delivery.recordedAt)}'),
            pw.Text('Time: ${_time(delivery.recordedAt)}'),
            pw.Text(
              'Delivery recorded by: ${recorderDisplayName(delivery.recordedByUserId, recorderNames)}',
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: const ['Bag', 'Weight', 'Weight recorded by'],
              data: [
                for (var index = 0; index < delivery.bagWeights.length; index++)
                  [
                    '${index + 1}',
                    '${delivery.bagWeights[index].toStringAsFixed(1)} kg',
                    recorderDisplayName(
                      delivery.recorderForBag(index),
                      recorderNames,
                    ),
                  ],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total bags: ${delivery.numberOfBags}\nTotal weight: ${delivery.totalWeight.toStringAsFixed(1)} kg',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text('Status: ${delivery.status.name}'),
          ],
        ),
      ),
    );
    return document.save();
  }

  Future<void> print(
    Delivery delivery, {
    String companyName = 'Company',
    Uint8List? logoBytes,
    Map<String, String> recorderNames = const {},
  }) async {
    final bytes = await buildPdf(
      delivery,
      companyName: companyName,
      logoBytes: logoBytes,
      recorderNames: recorderNames,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${_safeFileName(companyName)}_Receipt_${delivery.id}.pdf',
    );
  }

  Future<void> printSupplierHistory(
    Supplier supplier,
    List<Delivery> deliveries, {
    String companyName = 'Company',
    Uint8List? logoBytes,
    Map<String, String> recorderNames = const {},
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Row(
          children: [
            if (logoBytes != null) ...[
              pw.SizedBox(
                width: 36,
                height: 36,
                child: pw.Image(
                  pw.MemoryImage(logoBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Text(
                '$companyName - Supplier History',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Text('Supplier: ${supplier.name}'),
          pw.Text('Supplier ID: ${supplier.id}'),
          pw.Text('Type: ${supplier.type.name}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Product', 'Bags', 'Weight', 'Recorded by'],
            data: deliveries
                .map(
                  (delivery) => [
                    _date(delivery.recordedAt),
                    delivery.product.name,
                    '${delivery.numberOfBags}',
                    '${delivery.totalWeight.toStringAsFixed(1)} kg',
                    recorderDisplayName(
                      delivery.recordedByUserId,
                      recorderNames,
                    ),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Total deliveries: ${deliveries.length}'),
          pw.Text(
            'Total bags: ${deliveries.fold<int>(0, (total, delivery) => total + delivery.numberOfBags)}',
          ),
          pw.Text(
            'Total weight: ${deliveries.fold<double>(0, (total, delivery) => total + delivery.totalWeight).toStringAsFixed(1)} kg',
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => document.save(),
      name: '${_safeFileName(companyName)}_Supplier_${supplier.id}.pdf',
    );
  }

  Future<bool> sendByWhatsApp(
    Delivery delivery, {
    String companyName = 'Company',
  }) async {
    final phone = delivery.supplier.phone?.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone == null || phone.isEmpty) return false;
    final text = Uri.encodeComponent(
      '$companyName receiving receipt\nReference: ${delivery.id}\nSupplier: ${delivery.supplier.name}\nProduct: ${delivery.product.name}\nBags: ${delivery.numberOfBags}\nTotal weight: ${delivery.totalWeight.toStringAsFixed(1)} kg\nDate: ${_date(delivery.recordedAt)}',
    );
    return launchUrl(
      Uri.parse('https://wa.me/$phone?text=$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String _time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  static String _safeFileName(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
