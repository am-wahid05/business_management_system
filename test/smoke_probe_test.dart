import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/bulk_receiving_input.dart';
import 'package:flutter_application_2/features/receiving/receipt_service.dart';
import 'package:flutter_application_2/features/secretary/bag_weight_validation.dart';

Supplier _supplier() => Supplier(
  id: 'sup-1',
  name: 'Kofi Farmer',
  type: SupplierType.farmer,
  town: 'Kumasi',
  district: 'Asokore',
  region: 'Ashanti',
);

Delivery _individual() => Delivery(
  id: 'del-1',
  supplier: _supplier(),
  product: Product.cashew,
  recordedAt: DateTime(2026, 3, 4, 9, 30),
  bagWeights: const [25.5, 30.0],
  recordedByUserId: 'user-1',
);

Delivery _bulk() => Delivery(
  id: 'del-bulk',
  supplier: _supplier(),
  product: Product.cocoa,
  recordedAt: DateTime(2026, 3, 4, 10, 15),
  // A bulk record genuinely has no bag weights; the model enforces this.
  bagWeights: const [],
  recordedByUserId: 'user-1',
  recordType: DeliveryRecordType.bulk,
  bulkTotalWeight: 1250.5,
  bulkBagCount: 42,
  notes: 'Weighing bridge run',
);

/// Pulls the literal strings out of a generated PDF so a test can assert on
/// what a receipt actually prints, not merely that a PDF was produced.
///
/// The PDF content stream is Flate-compressed, so it is inflated first. Without
/// that step this helper would return compressed binary and every assertion
/// below would fail for the wrong reason.
String pdfText(List<int> bytes) {
  final raw = String.fromCharCodes(bytes);
  final recovered = StringBuffer();
  for (final match in RegExp(
    r'stream\r?\n(.*?)endstream',
    dotAll: true,
  ).allMatches(raw)) {
    final compressed = match.group(1)!.codeUnits;
    try {
      recovered
        ..write(String.fromCharCodes(ZLibDecoder().convert(compressed)))
        ..write('\n');
    } catch (_) {
      // Not every stream is compressed; fall back to the raw text.
      recovered
        ..write(match.group(1)!)
        ..write('\n');
    }
  }
  final strings = <String>[];
  for (final inner in RegExp(
    r'\(((?:[^()\\]|\\.)*)\)',
  ).allMatches(recovered.toString())) {
    strings.add(inner.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'));
  }
  // A PDF emits each word as its own text-showing operator, so "25.5 kg" is
  // stored as two separate strings. Joining them with single spaces and
  // collapsing runs of whitespace lets assertions read like the printed page.
  return strings.join(' ').replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  group('Bag weight validation', () {
    test('blank optional boxes are skipped, not treated as zero bags', () {
      expect(parseEnteredBagWeights(const ['', '  ', '25.5']), [25.5]);
    });

    test('rejects zero, negative and malformed entries consistently', () {
      for (final bad in <List<String>>[
        ['0'],
        ['-5'],
        ['abc'],
        ['25.5', '0'],
        ['25.5', '-1'],
        ['25.5', 'heavy'],
      ]) {
        expect(
          () => parseEnteredBagWeights(bad),
          throwsA(isA<BagWeightValidationException>()),
          reason: 'must reject $bad',
        );
      }
    });

    test('requires at least one weight so a bag count is never zero', () {
      expect(
        () => parseEnteredBagWeights(const ['', '  ']),
        throwsA(
          isA<BagWeightValidationException>().having(
            (e) => e.message,
            'message',
            contains('at least one bag weight'),
          ),
        ),
      );
    });
  });

  group('Bulk receiving validation', () {
    test('accepts a whole bag count and a positive total', () {
      final input = parseBulkReceivingInput(
        bags: '42',
        totalWeight: '1,250.5',
        notes: '  bridge run  ',
      );
      expect(input.bagCount, 42);
      expect(input.totalWeight, 1250.5);
      expect(input.notes, 'bridge run');
    });

    test('rejects zero, negative and malformed bulk values', () {
      for (final entry in <List<String>>[
        ['42', '0'],
        ['42', '-10'],
        ['42', 'heavy'],
        ['0', '100'],
        ['-3', '100'],
        ['4.5', '100'],
        ['', '100'],
      ]) {
        expect(
          () => parseBulkReceivingInput(bags: entry[0], totalWeight: entry[1]),
          throwsA(isA<BulkReceivingValidationException>()),
          reason: 'must reject ${entry.join(' / ')}',
        );
      }
    });
  });

  group('Bulk receipt printing', () {
    test(
      'a bulk receipt shows bulk totals, never an empty bag table',
      () async {
        final text = pdfText(
          await const ReceiptService().buildPdf(
            _bulk(),
            companyName: 'Acum Ltd',
          ),
        );
        expect(text, contains('Acum Ltd'));
        expect(text, contains('1250.5 kg'));
        expect(text, contains('42'));
        expect(text.toLowerCase(), contains('weighing-bridge'));
      },
    );

    test('an individual receipt still lists each bag weight', () async {
      final text = pdfText(
        await const ReceiptService().buildPdf(
          _individual(),
          companyName: 'Acum Ltd',
        ),
      );
      expect(text, contains('25.5 kg'));
      expect(text, contains('30.0 kg'));
      expect(
        text,
        contains('55.5 kg'),
        reason: 'total weight must still print',
      );
    });
  });
}
