import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/auth/active_company_context.dart';
import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/receiving/paper_layout.dart';
import 'package:flutter_application_2/features/receiving/paper_size.dart';
import 'package:flutter_application_2/features/receiving/print_settings_service.dart';
import 'package:flutter_application_2/features/receiving/receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  final supplier = Supplier(
    id: 'SUP-PDF-1',
    name: 'Ama Mensah',
    type: SupplierType.farmer,
    town: 'Tamale',
    district: 'Tamale Metro',
    region: 'Northern',
    phone: '0241234567',
  );

  test('individual receipt PDF contains the saved receipt fields', () async {
    final delivery = Delivery(
      id: 'PDF-IND-001',
      supplier: supplier,
      product: Product(id: 'cocoa', name: 'Cocoa'),
      recordedAt: DateTime(2026, 10, 2, 14, 35),
      bagWeights: const [25.5, 30.0, 20.25],
      recordedByUserId: 'secretary-1',
    );

    final bytes = await const ReceiptService().buildPdf(
      delivery,
      companyName: 'Northern Produce Ltd',
    );
    final text = _pdfSearchText(bytes);

    expect(bytes, isA<Uint8List>());
    expect(bytes.take(5).toList(), <int>[0x25, 0x50, 0x44, 0x46, 0x2D]);
    expect(
      latin1.decode(bytes, allowInvalid: true).startsWith('%PDF-'),
      isTrue,
    );
    expect(text, contains('PDF-IND-001'));
    expect(text, contains('Northern Produce Ltd'));
    expect(text, contains('Ama Mensah'));
    expect(text, contains('Cocoa'));
    expect(text, contains('25.5 kg'));
    expect(text, contains('30.0 kg'));
    expect(text, contains('20.3 kg'));
    expect(text, contains('Total bags: 3'));
    expect(text, contains('Total weight: 75.8 kg'));
    expect(latin1.decode(bytes, allowInvalid: true), contains('%%EOF'));
  });

  test('bulk receipt PDF contains stored bulk fields and notes', () async {
    final delivery = Delivery(
      id: 'PDF-BULK-001',
      supplier: supplier,
      product: Product(id: 'cashew', name: 'Cashew'),
      recordedAt: DateTime(2026, 10, 2, 15, 10),
      bagWeights: const [],
      recordedByUserId: 'secretary-1',
      recordType: DeliveryRecordType.bulk,
      bulkTotalWeight: 62430,
      bulkBagCount: 1250,
      notes: 'Scale ticket 88',
    );

    final bytes = await const ReceiptService().buildPdf(
      delivery,
      companyName: 'Northern Produce Ltd',
    );
    final text = _pdfSearchText(bytes);

    expect(bytes, isA<Uint8List>());
    expect(bytes.take(5).toList(), <int>[0x25, 0x50, 0x44, 0x46, 0x2D]);
    expect(
      latin1.decode(bytes, allowInvalid: true).startsWith('%PDF-'),
      isTrue,
    );
    expect(text, contains('PDF-BULK-001'));
    expect(text, contains('Weighing-bridge (bulk) entry'));
    expect(text, contains('Cashew'));
    expect(text, contains('Number of bags'));
    expect(text, contains('1250'));
    expect(text, contains('62430.0 kg'));
    expect(text, contains('Scale ticket 88'));
    expect(latin1.decode(bytes, allowInvalid: true), contains('%%EOF'));
  });

  group('the PDF stays binary all the way to the printer', () {
    Delivery receipt() => Delivery(
      id: 'PDF-BIN-001',
      supplier: supplier,
      product: Product(id: 'cocoa', name: 'Cocoa'),
      recordedAt: DateTime(2026, 10, 2, 14, 35),
      bagWeights: const [25.5, 30.0],
      recordedByUserId: 'secretary-1',
    );

    test('the generator returns binary bytes, never text', () async {
      final bytes = await const ReceiptService().buildPdf(
        receipt(),
        companyName: 'Northern Produce Ltd',
      );

      // Binary, and of real document size. A PDF that had been round-tripped
      // through a string would not survive the header comparison below.
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(512));

      // The bytes the caller receives are the bytes the engine produced: the
      // service must not rewrite the document on the way out.
      expect(bytes.take(5), orderedEquals(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('the document carries a complete PDF envelope', () async {
      final bytes = await const ReceiptService().buildPdf(
        receipt(),
        companyName: 'Northern Produce Ltd',
      );
      final asLatin1 = latin1.decode(bytes, allowInvalid: true);

      expect(asLatin1.startsWith('%PDF-1.'), isTrue);
      expect(asLatin1, contains('%%EOF'));
      expect(asLatin1, contains('startxref'));
      // No literal "trailer" keyword is asserted: the pdf package writes a
      // cross-reference stream for modern versions, where the trailer
      // dictionary lives inside that stream rather than in a plain keyword.
    });

    test('regenerating the same receipt yields the same content', () async {
      // Preview and print both call buildPdf, and both must describe the same
      // document. The bytes themselves are deliberately NOT compared for
      // equality: every PDF the engine writes embeds a CreationDate
      // (`/CreationDate(D:...)`), so two runs one second apart differ in exactly
      // that field. What must be stable is the business content, which is what
      // a reader would ever notice the two documents disagreeing about.
      final first = _pdfSearchText(
        await const ReceiptService().buildPdf(
          receipt(),
          companyName: 'Northern Produce Ltd',
        ),
      );
      final second = _pdfSearchText(
        await const ReceiptService().buildPdf(
          receipt(),
          companyName: 'Northern Produce Ltd',
        ),
      );
      expect(second, first);
      expect(first, contains('PDF-BIN-001'));
    });

    test('supplier history is binary too', () async {
      final bytes = await const ReceiptService().buildSupplierHistoryPdf(
        supplier,
        [receipt()],
        companyName: 'Northern Produce Ltd',
      );
      expect(bytes, isA<Uint8List>());
      expect(bytes.take(5), orderedEquals(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]));
      expect(latin1.decode(bytes, allowInvalid: true), contains('%%EOF'));
    });

    test('no source file converts PDF bytes to text', () {
      // Guards the actual regression. These are the calls that turn a binary
      // PDF into printable text, which is what produced raw "%PDF-1.7 ... stream"
      // output on the printer. None may come back into the printing pipeline.
      const offenders = <String>[
        'String.fromCharCodes',
        'utf8.decode',
        'writeAsString',
        'latin1.encode',
        'List<int>.from(',
      ];
      for (final file in _receiptPipelineSources) {
        final source = file.readAsStringSync();
        for (final offender in offenders) {
          expect(
            source.contains(offender),
            isFalse,
            reason:
                '${file.path} must not contain "$offender": PDF bytes have to '
                'stay binary end to end.',
          );
        }
      }
    });

    test('printing keeps the classic dialog and never mutates the header', () {
      final source = File('lib/features/receiving/receipt_service.dart')
          .readAsStringSync();
      // The modern PrintDlgEx path is not used: on Windows 11 it disables
      // preview for Win32 apps and takes the newest, least exercised branch.
      // Matched as a named argument so the explanatory comment, which names the
      // flag on purpose, does not count as using it.
      expect(
        RegExp(r'windowsModernDialog\s*:').hasMatch(source),
        isFalse,
        reason: 'layoutPdf must not opt into the modern Windows dialog',
      );
      // The header version byte is never rewritten.
      expect(source.contains('_asPdf17'), isFalse);
      expect(RegExp(r'\[\s*7\s*\]\s*=').hasMatch(source), isFalse);
    });
  });

  group('the preview is a normal route the user can leave', () {
    // The preview must never trap the user. It is pushed on top of the screen
    // they came from, so Back pops exactly that route and nothing underneath is
    // rebuilt, cleared or signed out.
    late Uint8List document;

    setUpAll(() async {
      document = await const ReceiptService().buildPdf(
        Delivery(
          id: 'PDF-BACK-1',
          supplier: Supplier(
            id: 'SUP-PDF-1',
            name: 'Ama Mensah',
            type: SupplierType.farmer,
            town: 'Tamale',
            district: 'Tamale Metro',
            region: 'Northern',
          ),
          product: Product(id: 'cocoa', name: 'Cocoa'),
          recordedAt: DateTime(2026, 10, 2, 14, 35),
          bagWeights: const [25.5],
          recordedByUserId: 'secretary-1',
        ),
        companyName: 'Northern Produce Ltd',
      );
    });

    testWidgets('Back returns to the screen the preview was opened from', (
      tester,
    ) async {
      var openPreviewButtonTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (homeContext) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    openPreviewButtonTaps++;
                    await ReceiptService.showPrintPreview(
                      homeContext,
                      document: document,
                      fileName: 'receipt.pdf',
                      title: 'Print receipt',
                      pageFormat: PdfPageFormat.a4,
                    );
                  },
                  child: const Text('Open preview'),
                ),
              ),
            ),
          ),
        ),
      );

      // The screen underneath, exactly as the user left it.
      expect(find.text('Open preview'), findsOneWidget);

      await tester.tap(find.text('Open preview'));
      // Deliberately pumped frame by frame rather than settled. The preview
      // rasterises continuously while it is on screen, so there is never a
      // settled frame to wait for; what matters here is that the route opened
      // and presented its chrome.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The preview is open, with a clearly labelled Back control.
      expect(openPreviewButtonTaps, 1);
      expect(find.text('Print receipt'), findsOneWidget);
      final back = find.byType(BackButton);
      expect(back, findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      // The reverse transition needs a further frame to finish and dispose the
      // preview route; until it is gone its (now inert) back button is still in
      // the tree.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      // Back pops the preview only. The original screen is still there, and the
      // state it was holding has not been reset.
      expect(find.text('Open preview'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Print receipt'), findsNothing);
    });

    test('every entry point opens the preview through this one helper', () {
      // Individual Receiving, Bulk Receiving, Print Records and Supplier
      // History must all land in the same preview route, otherwise the Back
      // button would only exist for some of them.
      final source = File('lib/features/receiving/receipt_service.dart')
          .readAsStringSync();
      expect(source.contains('showPrintPreview('), isTrue);
      expect(source.contains('previewDelivery('), isTrue);
      expect(source.contains('previewSupplierHistory('), isTrue);

      for (final caller in const [
        'lib/features/secretary/delivery_detail_screen.dart',
        'lib/features/secretary/secretary_print_records_screen.dart',
        'lib/features/suppliers/supplier_profile_screen.dart',
      ]) {
        final callerSource = File(caller).readAsStringSync();
        expect(
          callerSource.contains('previewDelivery(') ||
              callerSource.contains('previewSupplierHistory('),
          isTrue,
          reason: '$caller must open the shared print preview',
        );
      }
    });
  });

  group('paper size drives the document geometry', () {
    Delivery receipt({int bags = 3}) => Delivery(
      id: 'PAPER-001',
      supplier: Supplier(
        id: 'SUP-PAPER-1',
        name: 'Ama Mensah',
        type: SupplierType.farmer,
        town: 'Tamale',
        district: 'Tamale Metro',
        region: 'Northern',
        phone: '0241234567',
      ),
      product: Product(id: 'cocoa', name: 'Cocoa'),
      recordedAt: DateTime(2026, 10, 2, 14, 35),
      bagWeights: [for (var i = 0; i < bags; i++) 25.0 + i],
      recordedByUserId: 'secretary-1',
    );

    // The MediaBox is plain text inside the document, so the finished page
    // geometry can be read back out of the binary without a PDF parser.
    ({double width, double height}) pageOf(Uint8List bytes) {
      final text = latin1.decode(bytes, allowInvalid: true);
      final match = RegExp(
        r'/MediaBox\s*\[\s*[\d.-]+\s+[\d.-]+\s+([\d.]+)\s+([\d.]+)\s*\]',
      ).firstMatch(text);
      expect(match, isNotNull, reason: 'document must declare a MediaBox');
      return (
        width: double.parse(match!.group(1)!),
        height: double.parse(match.group(2)!),
      );
    }

    test('58 mm produces a 58 mm wide page', () async {
      final bytes = await const ReceiptService().buildPdf(
        receipt(),
        companyName: 'Northern Produce Ltd',
        paper: PaperSize.thermal58,
      );
      expect(bytes, isA<Uint8List>());
      // 58 mm expressed in PostScript points.
      expect(pageOf(bytes).width, closeTo(58 * 72 / 25.4, 0.5));
    });

    test('80 mm produces an 80 mm wide page', () async {
      final bytes = await const ReceiptService().buildPdf(
        receipt(),
        companyName: 'Northern Produce Ltd',
        paper: PaperSize.thermal80,
      );
      expect(pageOf(bytes).width, closeTo(80 * 72 / 25.4, 0.5));
    });

    test('A4 keeps the page this application has always produced', () async {
      final bytes = await const ReceiptService().buildPdf(
        receipt(),
        companyName: 'Northern Produce Ltd',
        paper: PaperSize.a4,
      );
      // PdfPageFormat.a4 is 595.28 x 841.89 points.
      expect(pageOf(bytes).width, closeTo(595.28, 1));
    });

    test('every supported paper size generates a valid document', () async {
      for (final paper in PaperSize.values) {
        final bytes = await const ReceiptService().buildPdf(
          receipt(),
          companyName: 'Northern Produce Ltd',
          paper: paper,
        );
        expect(bytes, isA<Uint8List>(), reason: '$paper must build');
        expect(
          bytes.length,
          greaterThan(256),
          reason: '$paper must not be an empty page',
        );
        expect(
          bytes.take(5),
          orderedEquals(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]),
          reason: '$paper must be a PDF',
        );
        expect(
          latin1.decode(bytes, allowInvalid: true),
          contains('%%EOF'),
          reason: '$paper must be complete',
        );
      }
    });

    test('a thermal receipt is not an A4 page in disguise', () async {
      // The point of a thermal layout: the page is sized to the roll.
      final thermal = await const ReceiptService().buildPdf(
        receipt(),
        paper: PaperSize.thermal80,
      );
      final sheet = await const ReceiptService().buildPdf(
        receipt(),
        paper: PaperSize.a4,
      );
      expect(pageOf(thermal).width, lessThan(pageOf(sheet).width));
    });

    test('a longer receipt grows its roll rather than clipping', () async {
      final short = pageOf(
        await const ReceiptService().buildPdf(
          receipt(bags: 1),
          paper: PaperSize.thermal80,
        ),
      );
      final long = pageOf(
        await const ReceiptService().buildPdf(
          receipt(bags: 12),
          paper: PaperSize.thermal80,
        ),
      );
      expect(
        long.height,
        greaterThan(short.height),
        reason: 'more bag rows must produce a longer roll',
      );
    });

    test('a thermal receipt still prints every business fact', () async {
      final text = _pdfSearchText(
        await const ReceiptService().buildPdf(
          receipt(),
          companyName: 'Northern Produce Ltd',
          paper: PaperSize.thermal58,
        ),
      );
      // A narrower layout must not silently drop information.
      expect(text, contains('PAPER-001'));
      expect(text, contains('Ama Mensah'));
      expect(text, contains('Cocoa'));
      expect(text, contains('Total bags: 3'));
      expect(text, contains('Northern Produce Ltd'));
    });

    test('a statement follows the configured sheet size', () async {
      final supplier = Supplier(
        id: 'SUP-PAPER-1',
        name: 'Ama Mensah',
        type: SupplierType.farmer,
        town: 'Tamale',
        district: 'Tamale Metro',
        region: 'Northern',
      );
      final a4 = await const ReceiptService().buildSupplierHistoryPdf(
        supplier,
        [receipt()],
        paper: PaperSize.a4,
      );
      final letter = await const ReceiptService().buildSupplierHistoryPdf(
        supplier,
        [receipt()],
        paper: PaperSize.letter,
      );
      expect(pageOf(a4).width, closeTo(595.28, 1));
      // Letter is 8.5in wide = 612 points, wider than A4.
      expect(pageOf(letter).width, closeTo(612, 1));
    });
  });

  group('company printing settings stay isolated', () {
    test('each company keeps its own paper choice', () {
      const companyA = CompanyPrintProfile(receiptPaper: PaperSize.thermal58);
      const companyB = CompanyPrintProfile(receiptPaper: PaperSize.thermal80);

      // Changing one must not reach the other: profiles are immutable values
      // and copyWith never edits the original in place.
      final updatedB = companyB.copyWith(receiptPaper: PaperSize.a5);
      expect(updatedB.receiptPaper, PaperSize.a5);
      expect(companyB.receiptPaper, PaperSize.thermal80);
      expect(companyA.receiptPaper, PaperSize.thermal58);
    });

    test('a profile round-trips through the stored columns', () {
      const saved = CompanyPrintProfile(
        receiptPaper: PaperSize.thermal58,
        reportPaper: PaperSize.letter,
        statementPaper: PaperSize.a5,
        showPreview: false,
      );
      final columns = saved.toCompanyColumns();
      expect(CompanyPrintProfile.fromCompanyRow(columns), saved);
    });

    test('a brand new company starts on sensible defaults', () {
      const fresh = CompanyPrintProfile();
      expect(fresh.receiptPaper, PaperSize.thermal80);
      expect(fresh.reportPaper, PaperSize.a4);
      expect(fresh.statementPaper, PaperSize.a4);
      expect(fresh.showPreview, isTrue);
    });

    test('an unreadable stored value falls back instead of failing', () {
      // A row written by an older build, or by hand, must still print.
      final profile = CompanyPrintProfile.fromCompanyRow({
        'receipt_paper_size': 'some-future-printer-size',
        'report_paper_size': null,
      });
      expect(profile.receiptPaper, PaperSize.thermal80);
      expect(profile.reportPaper, PaperSize.a4);
    });

    test(
      'resolved settings are remembered against the company, not globally',
      () {
        PrintPreferences.clear();
        addTearDown(PrintPreferences.clear);

        // Two companies, two different papers, both remembered at once.
        PrintPreferences.remember(
          'company-a',
          const CompanyPrintProfile(receiptPaper: PaperSize.thermal58),
        );
        PrintPreferences.remember(
          'company-b',
          const CompanyPrintProfile(receiptPaper: PaperSize.thermal80),
        );

        // Switching back and forth must return each company's own value, which
        // is what the per-company cache guarantees.
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-a'),
          ),
          completion(
            const CompanyPrintProfile(receiptPaper: PaperSize.thermal58),
          ),
        );
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-b'),
          ),
          completion(
            const CompanyPrintProfile(receiptPaper: PaperSize.thermal80),
          ),
        );
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-a'),
          ),
          completion(
            const CompanyPrintProfile(receiptPaper: PaperSize.thermal58),
          ),
        );
      },
    );

    test(
      'logout clears cached profiles so the next session cannot inherit them',
      () {
        PrintPreferences.clear();
        addTearDown(PrintPreferences.clear);

        // Two companies with fully distinct profiles, so defaults can never
        // be mistaken for either company's own settings.
        const profileA = CompanyPrintProfile(
          receiptPaper: PaperSize.thermal58,
          reportPaper: PaperSize.letter,
          statementPaper: PaperSize.a5,
          showPreview: false,
        );
        const profileB = CompanyPrintProfile(
          receiptPaper: PaperSize.thermal80,
          reportPaper: PaperSize.legal,
          statementPaper: PaperSize.a4,
          showPreview: true,
        );

        // A signs in and its settings are cached; B likewise.
        PrintPreferences.remember('company-a', profileA);
        PrintPreferences.remember('company-b', profileB);
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-a'),
          ),
          completion(profileA),
        );
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-b'),
          ),
          completion(profileB),
        );

        // The canonical logout path drops every cached profile plus the
        // remembered company context.
        PrintPreferences.clear();

        // Company A no longer resolves to its stale 58 mm profile.
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-a'),
          ),
          completion(const CompanyPrintProfile()),
        );

        // User/company B signs in afterwards with only its own settings: B
        // gets exactly its own profile (report legal, not the default a4),
        // while A still resolves to defaults rather than leaking back.
        PrintPreferences.remember('company-b', profileB);
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-b'),
          ),
          completion(profileB),
        );
        expect(
          PrintPreferences.current(
            client: null,
            context: _contextFor('company-a'),
          ),
          completion(const CompanyPrintProfile()),
        );
      },
    );

    test('the option lists match what the app can actually print', () {
      for (final size in [PaperSize.thermal58, PaperSize.thermal80]) {
        expect(PaperSize.receiptOptions, contains(size));
      }
      // A statement is never offered a thermal roll: there is no honest 58 mm
      // layout for a multi-row table.
      expect(PaperSize.sheetOptions.any((size) => size.isThermal), isFalse);
    });

    test('a thermal layout uses the width of its own roll', () {
      final narrow = PaperLayout.forPaper(PaperSize.thermal58);
      final wide = PaperLayout.forPaper(PaperSize.thermal80);
      // 80 mm must offer more usable width than 58 mm, not the same layout
      // scaled down.
      expect(narrow.contentWidthPt, lessThan(wide.contentWidthPt));
      expect(wide.contentWidthPt, greaterThan(200));
    });
  });
}

/// A minimal company context whose active user belongs to [companyId].
ActiveCompanyContext _contextFor(String companyId) => ActiveCompanyContext(
  AppUser(
    id: 'user-1',
    username: 'user',
    displayName: 'User',
    role: UserRole.admin,
    isActive: true,
    companyId: companyId,
  ),
);

/// The files that make up the receipt build/preview/print pipeline.
///
/// Read by the source-scanning test above so a future edit cannot quietly
/// reintroduce a text conversion somewhere along the chain.
List<File> get _receiptPipelineSources => [
  File('lib/features/receiving/receipt_service.dart'),
  File('lib/features/secretary/delivery_detail_screen.dart'),
  File('lib/features/secretary/secretary_print_records_screen.dart'),
  File('lib/features/suppliers/supplier_profile_screen.dart'),
];

/// The receipt service deliberately creates an uncompressed PDF so Windows
/// print jobs remain easy to diagnose. Extract its literal PDF strings here
/// instead of treating the whole binary file as plain text; page text is
/// emitted as `(text)TJ` operators.
String _pdfLiteralStrings(List<int> bytes) {
  final output = StringBuffer();
  var index = 0;

  while (index < bytes.length) {
    if (bytes[index] != 0x28) {
      index++;
      continue;
    }

    index++;
    final value = <int>[];
    var depth = 1;
    while (index < bytes.length && depth > 0) {
      final byte = bytes[index++];
      if (byte == 0x5c) {
        if (index >= bytes.length) break;
        final escaped = bytes[index++];
        value.add(switch (escaped) {
          0x6e => 0x0a,
          0x72 => 0x0d,
          0x74 => 0x09,
          0x62 => 0x08,
          0x66 => 0x0c,
          _ => escaped,
        });
      } else if (byte == 0x28) {
        depth++;
        value.add(byte);
      } else if (byte == 0x29) {
        depth--;
        if (depth > 0) value.add(byte);
      } else {
        value.add(byte);
      }
    }

    if (depth == 0) {
      output
        ..write(latin1.decode(value, allowInvalid: true))
        ..write('\n');
    }
  }

  return output.toString();
}

String _pdfSearchText(List<int> bytes) =>
    _pdfLiteralStrings(bytes).replaceAll(RegExp(r'\s+'), ' ');
