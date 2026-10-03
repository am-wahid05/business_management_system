import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/imports/excel_import_service.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late ExcelImportService service;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
        CREATE TABLE deliveries (
          id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL,
          recorded_at TEXT NOT NULL, recorded_by_user_id TEXT, status TEXT NOT NULL,
          synchronization_status TEXT NOT NULL, supplier_name TEXT NOT NULL, product_name TEXT NOT NULL,
          supplier_type TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
      ''');
          await database.execute('''
        CREATE TABLE delivery_bag_weights (
          delivery_id TEXT NOT NULL, bag_number INTEGER NOT NULL, weight REAL NOT NULL,
          PRIMARY KEY (delivery_id, bag_number)
        )
      ''');
          await database.execute('''
        CREATE TABLE import_logs (
          id TEXT PRIMARY KEY, filename TEXT NOT NULL, imported_at TEXT NOT NULL,
          imported_by_user_id TEXT NOT NULL, rows_total INTEGER NOT NULL,
          rows_imported INTEGER NOT NULL, rows_skipped INTEGER NOT NULL, rows_failed INTEGER NOT NULL
        )
      ''');
          await database.execute('''
        CREATE TABLE suppliers (
          internal_id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL UNIQUE,
          normalized_name TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
          phone TEXT, town TEXT NOT NULL DEFAULT '', district TEXT NOT NULL DEFAULT '',
          region TEXT NOT NULL DEFAULT '', notes TEXT, is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          synchronization_status TEXT NOT NULL, synchronization_error TEXT
        )
      ''');
          await database.execute(
            'CREATE TABLE local_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final deliveryRepository = DeliveryRepository(database);
    final supplierRepository = SupplierRepository(database: database);
    service = ExcelImportService(
      database: database,
      deliveryRepository: deliveryRepository,
      userId: 'admin-1',
      receivingService: ReceivingService(
        database: database,
        supplierRepository: supplierRepository,
      ),
    );
  });

  tearDown(() => database.close());

  test('reads sheets, validates mapped rows, imports valid records, and logs summary', () async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Historical'];
    sheet.appendRow(
      [
        'Date',
        'Supplier ID',
        'Supplier Name',
        'Supplier Type',
        'Town',
        'District',
        'Region',
        'Product ID',
        'Product',
        'Bag Weights',
        'Recorded By',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow(
      [
        '2026-09-20',
        'ALB-000001',
        'Ibrahim Mensah',
        'Aggregator',
        'Techiman',
        'Techiman Municipal',
        'Bono East',
        'cashew',
        'Cashew',
        '82.5,79.8',
        'legacy',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow(
      [
        'bad-date',
        'ALB-000002',
        'Invalid',
        'Farmer',
        'Town',
        'District',
        'Region',
        'cocoa',
        'Cocoa',
        '50',
        'legacy',
      ].map(TextCellValue.new).toList(),
    );

    final parsed = service.readWorkbook(
      Uint8List.fromList(workbook.encode()!),
      'history.xlsx',
    );
    final source = parsed.sheets['Historical']!;
    final mapping = ImportMapping({
      ImportField.date: 'Date',
      ImportField.supplierId: 'Supplier ID',
      ImportField.supplierName: 'Supplier Name',
      ImportField.supplierType: 'Supplier Type',
      ImportField.town: 'Town',
      ImportField.district: 'District',
      ImportField.region: 'Region',
      ImportField.productId: 'Product ID',
      ImportField.productName: 'Product',
      ImportField.bagWeights: 'Bag Weights',
      ImportField.recordedBy: 'Recorded By',
    });
    final validation = service.validate(source, mapping);

    expect(parsed.sheets.keys, contains('Historical'));
    expect(validation.validCount, 1);
    expect(validation.failedCount, 1);

    final summary = await service.importValid('history.xlsx', validation);
    expect(summary.imported, 1);
    expect(summary.failed, 1);
    expect((await database.query('import_logs')).length, 1);
    expect(await service.deliveryRepository.count(), 1);
    expect(await database.query('suppliers'), hasLength(1));
  });

  test(
    'creates one supplier profile and reuses it for normalized names',
    () async {
      final rows = [
        _importRow('2026-09-20', 'Ibrahim Mensah', '80,70'),
        _importRow('2026-09-21', '  ibrahim   mensah ', '75'),
      ];
      final validation = ImportValidation(
        rows: rows
            .asMap()
            .entries
            .map(
              (entry) => ImportRowResult(
                rowNumber: entry.key + 2,
                delivery: entry.value,
              ),
            )
            .toList(),
      );

      final summary = await service.importValid('suppliers.xlsx', validation);

      expect(summary.imported, 2);
      final suppliers = await database.query('suppliers');
      expect(suppliers, hasLength(1));
      final deliveries = await database.query(
        'deliveries',
        orderBy: 'recorded_at',
      );
      expect(deliveries, hasLength(2));
      expect(deliveries[0]['supplier_id'], deliveries[1]['supplier_id']);
    },
  );

  test('skips a likely duplicate without overwriting it', () async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow(
      [
        'Date',
        'Supplier ID',
        'Supplier Name',
        'Product ID',
        'Product',
        'Bag Weights',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow(
      [
        '2026-09-20',
        'ALB-000001',
        'Ibrahim Mensah',
        'cashew',
        'Cashew',
        '80,70',
      ].map(TextCellValue.new).toList(),
    );
    final parsed = service.readWorkbook(
      Uint8List.fromList(workbook.encode()!),
      'duplicate.xlsx',
    );
    final mapping = ImportMapping({
      ImportField.date: 'Date',
      ImportField.supplierId: 'Supplier ID',
      ImportField.supplierName: 'Supplier Name',
      ImportField.productId: 'Product ID',
      ImportField.productName: 'Product',
      ImportField.bagWeights: 'Bag Weights',
    });
    final first = service.validate(parsed.sheets['Sheet1']!, mapping);
    await service.importValid('duplicate.xlsx', first);
    final second = service.validate(parsed.sheets['Sheet1']!, mapping);
    final summary = await service.importValid('duplicate.xlsx', second);

    expect(summary.imported, 0);
    expect(summary.skipped, 1);
    expect(await service.deliveryRepository.count(), 1);
  });
}

Delivery _importRow(
  String date,
  String supplierName,
  String weights,
) => Delivery(
  id: 'historical-${DateTime.now().microsecondsSinceEpoch}-${supplierName.hashCode}',
  supplier: Supplier(
    id: '',
    name: supplierName,
    type: SupplierType.aggregator,
    town: 'Techiman',
    district: 'Techiman Municipal',
    region: 'Bono East',
  ),
  product: Product(id: 'cashew', name: 'Cashew'),
  recordedAt: DateTime.parse(date),
  bagWeights: weights.split(',').map(double.parse).toList(),
  recordedByUserId: 'legacy',
);
