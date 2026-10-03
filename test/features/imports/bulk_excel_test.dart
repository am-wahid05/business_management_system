import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/exports/excel_export_service.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/import_header_detector.dart';
import 'package:flutter_application_2/features/imports/import_models.dart';
import 'package:flutter_application_2/features/receiving/bulk_receiving_input.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_row.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 verification: bulk Excel import/export and bulk spreadsheet display.
void main() {
  final supplier = Supplier(
    internalId: 's1',
    id: 'S-1',
    name: 'John Mensah',
    type: SupplierType.farmer,
    town: 'Kumasi',
    district: 'Ashanti',
    region: 'Ashanti',
  );
  final product = Product(id: 'p1', name: 'Cocoa');

  Delivery individual() => Delivery(
    id: 'd-ind',
    supplier: supplier,
    product: product,
    recordedAt: DateTime(2026, 9, 26),
    bagWeights: const [48.5, 51.2, 49.9],
    recordedByUserId: 'user-secretary',
  );

  Delivery bulk() => Delivery(
    id: 'd-bulk',
    supplier: supplier,
    product: product,
    recordedAt: DateTime(2026, 9, 26),
    bagWeights: const [],
    recordedByUserId: 'user-secretary',
    recordType: DeliveryRecordType.bulk,
    bulkTotalWeight: 62430,
    bulkBagCount: 1250,
    notes: 'Tarp lot',
  );

  group('record type column detection', () {
    test('Record Type maps to the record type field', () {
      expect(detectFieldForHeader('Record Type'), ImportField.recordType);
    });

    test('Number of Bags maps to the bag count, not to bag weights', () {
      final field = detectFieldForHeader('Number of Bags');
      expect(field, ImportField.bagCount);
      expect(field, isNot(ImportField.bagWeights));
    });

    test('Notes maps to notes', () {
      expect(detectFieldForHeader('Notes'), ImportField.notes);
    });

    test('a Record Type column does not disturb other columns', () {
      final mapping = guessMapping(const [
        'Record Type',
        'Date',
        'Supplier Name',
        'Product',
        'Number of Bags',
        'Total Weight',
        'Notes',
      ]);
      expect(mapping.column(ImportField.recordType), 'Record Type');
      expect(mapping.column(ImportField.bagCount), 'Number of Bags');
      expect(mapping.column(ImportField.totalWeight), 'Total Weight');
      expect(mapping.column(ImportField.notes), 'Notes');
    });
  });

  group('record type cell values', () {
    test('bulk wording selects a bulk record', () {
      for (final value in [
        'Bulk',
        'bulk',
        ' BULK ',
        'Bulk / Weighing Bridge',
        'weighing bridge',
      ]) {
        expect(
          parseImportRecordType(value),
          DeliveryRecordType.bulk,
          reason: '"$value" should import as bulk',
        );
      }
    });

    test('anything else, including blank, stays individual', () {
      for (final value in [null, '', '   ', 'Individual', 'anything']) {
        expect(
          parseImportRecordType(value),
          DeliveryRecordType.individual,
          reason: '"$value" should import as individual',
        );
      }
    });
  });

  group('bulk Excel import', () {
    test('a bulk row stores the total and bag count with no bag weights', () {
      final input = parseBulkReceivingInput(bags: '1250', totalWeight: '62430');
      expect(input.bagCount, 1250);
      expect(input.totalWeight, 62430);
    });

    test('a bulk import rejects zero or negative bags', () {
      expect(
        () => parseBulkReceivingInput(bags: '0', totalWeight: '100'),
        throwsA(isA<BulkReceivingValidationException>()),
      );
    });

    test('a bulk import rejects a zero or missing weight', () {
      expect(
        () => parseBulkReceivingInput(bags: '10', totalWeight: '0'),
        throwsA(isA<BulkReceivingValidationException>()),
      );
      expect(
        () => parseBulkReceivingInput(bags: '10', totalWeight: ''),
        throwsA(isA<BulkReceivingValidationException>()),
      );
    });

    test('a bulk import never produces bag weights', () {
      // 1,250 bags must never be expanded into 1,250 weights.
      expect(bulk().bagWeights, isEmpty);
      expect(bulk().numberOfBags, 1250);
    });
  });

  group('Excel export', () {
    test('the record type label is written for both kinds', () {
      expect(excelRecordTypeLabel(DeliveryRecordType.individual), 'Individual');
      expect(excelRecordTypeLabel(DeliveryRecordType.bulk), 'Bulk');
    });
  });

  group('spreadsheet display', () {
    test('a bulk delivery displays as bulk with its total and bag count', () {
      final row = SpreadsheetRow.fromDelivery(bulk(), recorderName: 'Ama');
      expect(row.isBulk, isTrue);
      expect(row.recordType, DeliveryRecordType.bulk);
      expect(row.totalWeight, 62430);
      expect(row.numberOfBags, 1250);
      expect(row.bulkTotalWeight, 62430);
    });

    test('a bulk row shows a marker instead of bag weights', () {
      final row = SpreadsheetRow.fromDelivery(bulk(), recorderName: 'Ama');
      expect(row.weights, SpreadsheetRow.bulkWeightsMarker);
      expect(row.parsedWeights, isNull);
    });

    test('an individual delivery is unchanged', () {
      final row = SpreadsheetRow.fromDelivery(individual(), recorderName: 'Ama');
      expect(row.isBulk, isFalse);
      expect(row.weights, '48.5,51.2,49.9');
      expect(row.parsedWeights, [48.5, 51.2, 49.9]);
      expect(row.totalWeight, 149.6);
      expect(row.numberOfBags, 3);
      expect(row.bulkTotalWeight, isNull);
    });

    test('a bulk row is not editable as individual bag weights', () {
      final row = SpreadsheetRow.fromDelivery(bulk(), recorderName: 'Ama');
      row.weights = '48.5,51.2';
      expect(row.isBulk, isTrue);
      // The authoritative total and bag count are still the stored ones.
      expect(row.totalWeight, 62430);
      expect(row.numberOfBags, 1250);
    });
  });

  group('recorder attribution and isolation', () {
    test('a bulk record keeps the authenticated recorder', () {
      expect(bulk().recordedByUserId, 'user-secretary');
    });

    test('a bulk record carries its own company', () {
      final companyA = bulk().copyWith(companyId: 'company-a');
      expect(companyA.companyId, 'company-a');
      expect(companyA.isBulk, isTrue);
    });
  });
}
