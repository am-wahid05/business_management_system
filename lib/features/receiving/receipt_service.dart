import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';
import 'paper_layout.dart';
import 'paper_size.dart';

/// Neutral label used when the active company does not provide a name.
/// Receipts are customer-facing, so tenant-specific branding must never be
/// hardcoded here.
String _companyLabel(String? companyName) {
  final name = companyName?.trim();
  return (name == null || name.isEmpty) ? 'Company' : name;
}

class ReceiptService {
  const ReceiptService();

  /// Returns the receipt exactly as the PDF engine wrote it, byte for byte.
  ///
  /// Nothing here re-encodes, decodes or rewrites the document. A PDF is a
  /// binary stream, and the single most damaging thing a caller could do to it
  /// is round-trip it through text. The returned [Uint8List] goes straight to
  /// the print/preview rasteriser, so it must stay binary from end to end.
  ///
  /// [paper] selects the medium. A4 keeps the layout this application has
  /// always produced, so existing customers are unaffected; the other sizes get
  /// a layout built for their own geometry rather than a shrunken A4.
  Future<Uint8List> buildPdf(
    Delivery delivery, {
    String? companyName,
    PaperSize paper = PaperSize.a4,
  }) async {
    final company = _companyLabel(companyName);
    // Use the PDF package's built-in Type1 fonts explicitly. This avoids a
    // platform-dependent fallback or a Flutter UI font being embedded with
    // malformed glyph mappings when Windows saves the print job as PDF.
    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );
    // A thermal roll has no declared height, so it is sized from the content it
    // is about to carry. Sheet sizes ignore this and use their real media height.
    final layout = _layoutFor(delivery, paper);
    final document = pw.Document(
      compress: false,
      title: 'Receiving receipt ${delivery.id}',
      author: company,
      creator: 'Business Management System',
    );
    document.addPage(
      pw.Page(
        pageFormat: layout.pageFormat,
        margin: layout.margin,
        theme: theme,
        build: (_) =>
            _receiptBody(delivery: delivery, company: company, layout: layout),
      ),
    );
    return _requirePdfBytes(await document.save());
  }

  /// The geometry one receipt will be laid out with.
  ///
  /// Computed once per document and reused by the generator, the preview and
  /// the print job, so all three necessarily agree on the page size. A thermal
  /// roll is measured from the content it is about to carry; a sheet uses its
  /// real media height.
  static PaperLayout _layoutFor(Delivery delivery, PaperSize paper) {
    if (!paper.isThermal) return PaperLayout.forPaper(paper);
    final probe = PaperLayout.forPaper(paper);
    return PaperLayout.forPaper(
      paper,
      contentHeightPt: estimateThermalHeightPt(
        layout: probe,
        infoRows: _infoRowCount(delivery),
        tableRows: delivery.isBulk ? 2 : delivery.bagWeights.length,
        headingLines: 2,
        hasDivider: true,
      ),
    );
  }

  /// How many label/value lines this receipt prints.
  static int _infoRowCount(Delivery delivery) {
    var count = 6; // reference, supplier, supplier id, product, date, time
    if (delivery.supplier.phone != null) count++;
    if (delivery.supplier.town.trim().isNotEmpty) count++;
    if (delivery.recordedByUserId != null) count++;
    return count;
  }

  /// The one receipt layout, resolved for the target medium.
  ///
  /// A thermal roll and a sheet are genuinely different documents, so they are
  /// rendered differently rather than one being scaled into the other. Both
  /// branches read the same delivery and print the same business facts: nothing
  /// is dropped or invented for either size.
  static pw.Widget _receiptBody({
    required Delivery delivery,
    required String company,
    required PaperLayout layout,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          company,
          style: pw.TextStyle(
            fontSize: layout.titleSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Receiving receipt',
          style: pw.TextStyle(fontSize: layout.smallSize + 4),
        ),
        pw.Divider(),
        if (layout.isThermal)
          ..._thermalFields(delivery, layout)
        else
          ..._sheetFields(delivery),
        pw.SizedBox(height: layout.isThermal ? 6 : 20),
        if (delivery.isBulk) ...[
          if (!layout.isThermal) ...[
            pw.Text(
              'Weighing-bridge (bulk) entry',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
          ],
          if (layout.isThermal)
            buildBagWeightTable(delivery, layout)
          else
            _sheetWeightsTable(delivery),
          if (delivery.notes != null && delivery.notes!.trim().isNotEmpty) ...[
            pw.SizedBox(height: layout.isThermal ? 4 : 10),
            pw.Text('Notes: ${delivery.notes}', style: layout.textStyle),
          ],
        ] else if (layout.isThermal)
          buildBagWeightTable(delivery, layout)
        else
          _sheetWeightsTable(delivery),
        pw.SizedBox(height: layout.isThermal ? 6 : 16),
        pw.Align(
          alignment: layout.isThermal
              ? pw.Alignment.center
              : pw.Alignment.centerRight,
          child: pw.Text(
            'Total bags: ${delivery.numberOfBags}\n'
            'Total weight: ${delivery.totalWeight.toStringAsFixed(1)} kg',
            textAlign: layout.isThermal
                ? pw.TextAlign.center
                : pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: layout.bodySize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: layout.isThermal ? 6 : 24),
        pw.Text('Status: ${delivery.status.name}', style: layout.textStyle),
        if (delivery.notes != null && delivery.notes!.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text('Notes: ${delivery.notes}', style: layout.textStyle),
        ],
      ],
    );
  }

  /// The label/value lines as printed on a sheet.
  ///
  /// This is the layout A4 has always produced, one line per fact, so a company
  /// already printing on A4 sees no change at all. A5, Letter and Legal reuse
  /// the same lines and simply give them less or more room.
  static List<pw.Widget> _sheetFields(Delivery delivery) => [
    pw.Text('Reference: ${delivery.id}'),
    pw.Text('Supplier/customer: ${delivery.supplier.name}'),
    pw.Text('Supplier ID: ${delivery.supplier.id}'),
    pw.Text('Supplier type: ${delivery.supplier.type.name}'),
    if (delivery.supplier.phone != null)
      pw.Text('Phone: ${delivery.supplier.phone}'),
    if (delivery.supplier.town.trim().isNotEmpty)
      pw.Text('Location: ${_location(delivery)}'),
    pw.Text('Product: ${delivery.product.name}'),
    pw.Text('Date: ${_date(delivery.recordedAt)}'),
    pw.Text('Time: ${_time(delivery.recordedAt)}'),
    if (delivery.recordedByUserId != null)
      pw.Text('Recorded by: ${delivery.recordedByUserId}'),
  ];

  /// The weights table as printed on a sheet.
  static pw.Widget _sheetWeightsTable(Delivery delivery) {
    if (delivery.isBulk) {
      return pw.TableHelper.fromTextArray(
        headers: const ['Measure', 'Value'],
        data: [
          ['Number of bags', '${delivery.numberOfBags}'],
          ['Total weight', '${delivery.totalWeight.toStringAsFixed(1)} kg'],
        ],
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: const ['Bag', 'Weight'],
      data: [
        for (var i = 0; i < delivery.bagWeights.length; i++)
          ['${i + 1}', '${delivery.bagWeights[i].toStringAsFixed(1)} kg'],
      ],
    );
  }

  /// The label/value block as printed on a continuous roll.
  static List<pw.Widget> _thermalFields(Delivery delivery, PaperLayout layout) {
    return [
      buildLabelValueBlock([
        PrintRow('Reference', delivery.id),
        PrintRow('Supplier', delivery.supplier.name),
        PrintRow('Supplier ID', delivery.supplier.id),
        PrintRow('Type', delivery.supplier.type.name),
        if (delivery.supplier.phone != null)
          PrintRow('Phone', delivery.supplier.phone!),
        if (delivery.supplier.town.trim().isNotEmpty)
          PrintRow('Location', _location(delivery)),
        PrintRow('Product', delivery.product.name),
        PrintRow('Date', _date(delivery.recordedAt)),
        PrintRow('Time', _time(delivery.recordedAt)),
        if (delivery.recordedByUserId != null)
          PrintRow('Recorded by', delivery.recordedByUserId!),
      ], layout),
    ];
  }

  Future<void> print(
    Delivery delivery, {
    String? companyName,
    PaperSize paper = PaperSize.a4,
  }) async {
    final bytes = await buildPdf(
      delivery,
      companyName: companyName,
      paper: paper,
    );
    await _sendToPrinter(
      bytes,
      fileName: 'Receipt_${delivery.id}.pdf',
      pageFormat: _layoutFor(delivery, paper).pageFormat,
    );
  }

  /// Builds the supplier history document.
  ///
  /// Extracted from the former print call so the preview and the print action
  /// are guaranteed to render the same document. There is still exactly one
  /// generator for this report; it is simply callable on its own.
  Future<Uint8List> buildSupplierHistoryPdf(
    Supplier supplier,
    List<Delivery> deliveries, {
    String? companyName,
    PaperSize paper = PaperSize.a4,
  }) async {
    final layout = PaperLayout.forPaper(paper);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: layout.pageFormat,
        margin: layout.margin,
        header: (_) => pw.Text(
          '${_companyLabel(companyName)} - Supplier History',
          style: pw.TextStyle(
            fontSize: layout.titleSize - 4,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Text('Supplier: ${supplier.name}'),
          pw.Text('Supplier ID: ${supplier.id}'),
          pw.Text('Type: ${supplier.type.name}'),
          pw.SizedBox(height: 16),
          buildSizedTable(
            layout: layout,
            headers: const ['Date', 'Product', 'Type', 'Bags', 'Weight'],
            data: deliveries
                .map(
                  (delivery) => [
                    _date(delivery.recordedAt),
                    delivery.product.name,
                    delivery.isBulk ? 'Bulk' : 'Individual',
                    '${delivery.numberOfBags}',
                    '${delivery.totalWeight.toStringAsFixed(1)} kg',
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
    return _requirePdfBytes(await document.save());
  }

  Future<void> printSupplierHistory(
    Supplier supplier,
    List<Delivery> deliveries, {
    String? companyName,
    PaperSize paper = PaperSize.a4,
  }) async {
    final bytes = await buildSupplierHistoryPdf(
      supplier,
      deliveries,
      companyName: companyName,
      paper: paper,
    );
    await _sendToPrinter(
      bytes,
      fileName: 'Supplier_History_${supplier.id}.pdf',
      pageFormat: PaperLayout.forPaper(paper).pageFormat,
    );
  }

  Future<bool> sendByWhatsApp(Delivery delivery, {String? companyName}) async {
    final phone = delivery.supplier.phone?.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone == null || phone.isEmpty) return false;
    final text = Uri.encodeComponent(
      '${_companyLabel(companyName)} receiving receipt\nReference: ${delivery.id}\nSupplier: ${delivery.supplier.name}\nProduct: ${delivery.product.name}\nBags: ${delivery.numberOfBags}\nTotal weight: ${delivery.totalWeight.toStringAsFixed(1)} kg\nDate: ${_date(delivery.recordedAt)}',
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

  /// Hands an already-built document to the Windows print dialog.
  ///
  /// [document] is passed through untouched: the same bytes that were built are
  /// the bytes the driver receives. The print path is deliberately left on the
  /// classic Windows print dialog. `windowsModernDialog` routes the job to
  /// `PrintDlgEx`, which on Windows 11 hands printing to the redesigned system
  /// dialog; upstream documents that this dialog unconditionally disables
  /// preview for Win32 apps and ignores the `IPrintDialogCallback` preview hook.
  /// It is also a much newer code path than the long-established `PrintDlg`
  /// route. Neither is wanted here: the user is always shown the in-app preview
  /// first, and printing must go through the well-trodden path.
  static Future<bool> _sendToPrinter(
    Uint8List document, {
    required String fileName,
    required PdfPageFormat pageFormat,
  }) => Printing.layoutPdf(
    // The document is already built at its final size, so the driver must not
    // re-lay it out against whatever paper it reports. That is how a finished
    // 80 mm receipt would otherwise be re-flowed to the printer's own default.
    format: pageFormat,
    dynamicLayout: false,
    onLayout: (_) async => document,
    name: fileName,
  );

  /// Asserts the generated bytes really are a PDF, and returns them unchanged.
  ///
  /// This deliberately does NOT normalise, rewrite or re-encode anything. An
  /// earlier version of this file rewrote the version byte in the `%PDF-x.y`
  /// header to try to influence the print driver. That was the wrong lever: the
  /// header is not what decides whether a driver renders a document, it only
  /// creates a mismatch between the declared version and the document
  /// catalogue. The bytes are now handed over exactly as produced, and this
  /// check exists purely to fail loudly if generation ever returns something
  /// that is not a PDF at all.
  static Uint8List _requirePdfBytes(Uint8List bytes) {
    const header = [0x25, 0x50, 0x44, 0x46, 0x2D]; // '%PDF-'
    var valid = bytes.length > header.length;
    for (var i = 0; valid && i < header.length; i++) {
      valid = bytes[i] == header[i];
    }
    if (!valid) {
      throw StateError('Generated document is not a valid PDF byte stream');
    }
    return bytes;
  }

  /// Opens the in-app print preview for an already-built document.
  ///
  /// [document] is the finished PDF, not a recipe. The preview therefore
  /// rasterises exactly the bytes that the print action will hand to the
  /// driver, so what is shown is what prints: there is no second renderer and no
  /// chance of the preview and the printout drifting apart.
  ///
  /// Page format and orientation changes are switched off for the same reason.
  /// The document is already built at the company's configured size, and letting
  /// the user change the format here would make the preview show something the
  /// print job never produces.
  ///
  /// [pageFormat] is the real geometry of [document], so a 58 mm receipt
  /// previews as a 58 mm receipt and an A4 statement previews as A4.
  ///
  /// The preview is pushed as its own route, so the way out is simply popping
  /// that route. Nothing is signed out, no form is reset and no data is
  /// touched: the screen underneath is the exact one the user left, still
  /// holding whatever they had entered or selected.
  static Future<void> showPrintPreview(
    BuildContext context, {
    required Uint8List document,
    required String fileName,
    required String title,
    required PdfPageFormat pageFormat,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        // [PdfPreview] returns a plain Column and brings no Scaffold or AppBar
        // of its own, so hosting it in one adds the back affordance without
        // disturbing how the document is rendered or how the print action bar
        // is laid out.
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: BackButton(
              onPressed: () => Navigator.of(routeContext).pop(),
            ),
          ),
          body: PdfPreview(
            build: (_) async => document,
            initialPageFormat: pageFormat,
            pdfFileName: fileName,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowSharing: false,
            allowPrinting: true,
            dynamicLayout: false,
            scrollViewDecoration: const BoxDecoration(color: Colors.white),
            pdfPreviewPageDecoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
            loadingWidget: const Center(child: CircularProgressIndicator()),
            onError: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This document could not be displayed for printing.\n\n$error',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the receipt and shows it in the print preview.
  Future<void> previewDelivery(
    BuildContext context,
    Delivery delivery, {
    String? companyName,
    PaperSize paper = PaperSize.a4,
  }) async {
    final bytes = await buildPdf(
      delivery,
      companyName: companyName,
      paper: paper,
    );
    if (!context.mounted) return;
    await showPrintPreview(
      context,
      document: bytes,
      fileName: 'Receipt_${delivery.id}.pdf',
      title: 'Print receipt',
      pageFormat: _layoutFor(delivery, paper).pageFormat,
    );
  }

  /// Builds the supplier history and shows it in the print preview.
  Future<void> previewSupplierHistory(
    BuildContext context,
    Supplier supplier,
    List<Delivery> deliveries, {
    String? companyName,
    PaperSize paper = PaperSize.a4,
  }) async {
    final bytes = await buildSupplierHistoryPdf(
      supplier,
      deliveries,
      companyName: companyName,
      paper: paper,
    );
    if (!context.mounted) return;
    await showPrintPreview(
      context,
      document: bytes,
      fileName: 'Supplier_History_${supplier.id}.pdf',
      title: 'Print supplier history',
      pageFormat: PaperLayout.forPaper(paper).pageFormat,
    );
  }

  static String _location(Delivery delivery) => [
    delivery.supplier.town,
    delivery.supplier.district,
    delivery.supplier.region,
  ].where((value) => value.trim().isNotEmpty).join(', ');
}
