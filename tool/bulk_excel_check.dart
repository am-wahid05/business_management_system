// Temporary verification harness for the Phase 3 bulk Excel + spreadsheet rules.
// Run with: dart run tool/bulk_excel_check.dart
import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/import_header_detector.dart';
import 'package:flutter_application_2/features/imports/import_models.dart';
import 'package:flutter_application_2/features/receiving/bulk_receiving_input.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_row.dart';

int _failures = 0;

void check(String name, bool condition) {
  if (condition) {
    print('PASS  $name');
  } else {
    _failures++;
    print('FAIL  $name');
  }
}

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

  final individual = Delivery(
    id: 'd-ind',
    supplier: supplier,
    product: product,
    recordedAt: DateTime(2026, 9, 26),
    bagWeights: const [48.5, 51.2, 49.9],
    recordedByUserId: 'user-secretary',
  );
  final bulk = Delivery(
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

  // --- header detection ---
  check(
    'Record Type maps to recordType',
    detectFieldForHeader('Record Type') == ImportField.recordType,
  );
  check(
    'Number of Bags maps to bagCount, not bagWeights',
    detectFieldForHeader('Number of Bags') == ImportField.bagCount &&
        detectFieldForHeader('Number of Bags') != ImportField.bagWeights,
  );
  check(
    'Notes maps to notes',
    detectFieldForHeader('Notes') == ImportField.notes,
  );

  final mapping = guessMapping(const [
    'Record Type',
    'Date',
    'Supplier Name',
    'Product',
    'Number of Bags',
    'Total Weight',
    'Notes',
  ]);
  check(
    'a Record Type column does not disturb other columns',
    mapping.column(ImportField.recordType) == 'Record Type' &&
        mapping.column(ImportField.bagCount) == 'Number of Bags' &&
        mapping.column(ImportField.totalWeight) == 'Total Weight' &&
        mapping.column(ImportField.notes) == 'Notes',
  );

  // --- record type cell values ---
  check(
    'bulk wording selects a bulk record',
    [
      'Bulk',
      'bulk',
      ' BULK ',
      'Bulk / Weighing Bridge',
      'weighing bridge',
    ].every((v) => parseImportRecordType(v) == DeliveryRecordType.bulk),
  );
  check(
    'anything else, including blank, stays individual',
    [
      null,
      '',
      '   ',
      'Individual',
      'anything',
    ].every((v) => parseImportRecordType(v) == DeliveryRecordType.individual),
  );

  // --- bulk import validation ---
  final input = parseBulkReceivingInput(bags: '1250', totalWeight: '62430');
  check(
    'a bulk row stores the total and bag count',
    input.bagCount == 1250 && input.totalWeight == 62430,
  );
  check(
    'bulk import rejects zero/negative bags',
    [
      () => parseBulkReceivingInput(bags: '0', totalWeight: '100'),
      () => parseBulkReceivingInput(bags: '-1', totalWeight: '100'),
      () => parseBulkReceivingInput(bags: 'x', totalWeight: '100'),
    ].every((f) {
      try {
        f();
        return false;
      } on BulkReceivingValidationException {
        return true;
      }
    }),
  );
  check(
    'bulk import rejects zero/negative/blank weight',
    ['0', '-5', ''].every((t) {
      try {
        parseBulkReceivingInput(bags: '10', totalWeight: t);
        return false;
      } on BulkReceivingValidationException {
        return true;
      }
    }),
  );
  check(
    'a bulk import never produces bag weights',
    bulk.bagWeights.isEmpty && bulk.numberOfBags == 1250,
  );

  // --- spreadsheet display ---
  final bulkRow = SpreadsheetRow.fromDelivery(bulk, recorderName: 'Ama');
  check(
    'a bulk row displays as bulk with its total and bag count',
    bulkRow.isBulk &&
        bulkRow.recordType == DeliveryRecordType.bulk &&
        bulkRow.totalWeight == 62430 &&
        bulkRow.numberOfBags == 1250 &&
        bulkRow.bulkTotalWeight == 62430,
  );
  check(
    'a bulk row shows a marker instead of bag weights',
    bulkRow.weights == SpreadsheetRow.bulkWeightsMarker &&
        bulkRow.parsedWeights == null,
  );

  final indRow = SpreadsheetRow.fromDelivery(individual, recorderName: 'Ama');
  check(
    'an individual row is unchanged',
    !indRow.isBulk &&
        indRow.weights == '48.5,51.2,49.9' &&
        indRow.parsedWeights!.length == 3 &&
        indRow.totalWeight == 149.6 &&
        indRow.numberOfBags == 3 &&
        indRow.bulkTotalWeight == null,
  );

  bulkRow.weights = '48.5,51.2';
  check(
    'a bulk row cannot be converted by editing weights',
    bulkRow.isBulk &&
        bulkRow.totalWeight == 62430 &&
        bulkRow.numberOfBags == 1250,
  );

  // --- recorder / company ---
  check(
    'a bulk record keeps the authenticated recorder',
    bulk.recordedByUserId == 'user-secretary',
  );
  final scoped = bulk.copyWith(companyId: 'company-a');
  check(
    'a bulk record carries its own company',
    scoped.companyId == 'company-a' && scoped.isBulk,
  );

  print('');
  print(_failures == 0 ? 'ALL CHECKS PASSED' : '$_failures CHECK(S) FAILED');
}
