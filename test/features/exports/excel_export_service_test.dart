import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/exports/excel_export_service.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Decodes an exported workbook straight from its bytes.
///
/// The bytes are read here rather than handed to a file-based helper so the
/// assertions cover exactly what was written to disk.
Excel decodeWorkbook(File file) => Excel.decodeBytes(file.readAsBytesSync());

/// The sheet the export writes its records to.
///
/// The workbook is created with a default empty `Sheet1` alongside the named
/// sheet, so the sheet is chosen by name. Taking whichever sheet happens to be
/// first would silently read the empty one and make every assertion pass for
/// the wrong reason.
Sheet receivingSheet(File file) {
  final workbook = decodeWorkbook(file);
  final sheet = workbook.tables['Receiving'];
  if (sheet == null) {
    throw StateError(
      'The workbook has no "Receiving" sheet; it has '
      '${workbook.tables.keys.toList()}.',
    );
  }
  return sheet;
}

/// Reads a whole column of the receiving sheet by header name.
///
/// Using the header keeps these assertions independent of column order, so a
/// sensible column reordering does not break every test. Cells are nullable in
/// this package, so a missing cell reads as an empty string rather than
/// throwing.
List<String> columnValues(File file, String header) {
  final rows = receivingSheet(file).rows;
  final headers = rows.first.map(_cellText).toList();
  final index = headers.indexOf(header);
  if (index == -1) {
    throw StateError('Column "$header" is missing from the workbook.');
  }
  return rows.skip(1).map((row) {
    if (index >= row.length) return '';
    return _cellText(row[index]);
  }).toList();
}

String _cellText(Data? cell) => cell?.value?.toString() ?? '';

/// The data rows of the first sheet, keyed by the first column.
List<String> dataRows(File file) => columnValues(file, 'Record Type');

/// Opens a fresh company-scoped database for each test.
Future<Database> openTestDatabase() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE suppliers (
            supplier_id TEXT NOT NULL,
            company_id TEXT,
            name TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            supplier_type TEXT NOT NULL,
            phone TEXT,
            town TEXT NOT NULL DEFAULT '',
            district TEXT NOT NULL DEFAULT '',
            region TEXT NOT NULL DEFAULT '',
            normalized_name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (company_id, supplier_id)
          )
        ''');
        await database.execute('''
          CREATE TABLE deliveries (
            id TEXT PRIMARY KEY, company_id TEXT,
            supplier_id TEXT NOT NULL, product_id TEXT NOT NULL,
            recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL,
            status TEXT NOT NULL, synchronization_status TEXT NOT NULL,
            supplier_name TEXT NOT NULL, product_name TEXT NOT NULL,
            supplier_type TEXT NOT NULL,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE delivery_bag_weights (
            delivery_id TEXT NOT NULL, company_id TEXT,
            bag_number INTEGER NOT NULL, weight REAL NOT NULL,
            PRIMARY KEY (delivery_id, bag_number)
          )
        ''');
      },
    ),
  );
}

void main() {
  late Database database;
  late Directory outputDirectory;
  late ExcelExportService service;

  /// Swapped per test so the company-isolation cases can change the active
  /// company without rebuilding the repository.
  String? activeCompanyId;

  setUp(() async {
    activeCompanyId = 'company-a';
    database = await openTestDatabase();
    outputDirectory = await Directory.systemTemp.createTemp(
      'excel-export-test-',
    );
    service = ExcelExportService(
      DeliveryRepository(database, companyIdProvider: () => activeCompanyId),
      directoryProvider: () async => outputDirectory,
      companyNameProvider: () => 'Company A',
    );
  });

  tearDown(() async {
    await database.close();
    if (outputDirectory.existsSync()) {
      await outputDirectory.delete(recursive: true);
    }
  });

  Supplier supplier({
    required String id,
    required String name,
    String? phone,
  }) => Supplier(
    id: id,
    name: name,
    type: SupplierType.aggregator,
    town: 'Techiman',
    district: 'Techiman Municipal',
    region: 'Bono East',
    phone: phone,
  );

  Future<void> addDelivery({
    required String id,
    required Supplier supplier,
    required DateTime recordedAt,
    String productId = 'PRD-CASHEW',
    String productName = 'Cashew',
  }) async {
    await service.deliveryRepository.save(
      Delivery(
        id: id,
        supplier: supplier,
        product: Product(id: productId, name: productName),
        recordedAt: recordedAt,
        bagWeights: [80],
        recordedByUserId: 'secretary',
      ),
    );
  }

  group('All records export', () {
    test('exports only the records inside the chosen range', () async {
      await addDelivery(
        id: 'inside',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );
      await addDelivery(
        id: 'before',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 1, 31),
      );
      await addDelivery(
        id: 'after',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 7, 1),
      );

      final file = await service.exportRange(
        DateTime(2026, 3, 1),
        DateTime(2026, 6, 30),
      );

      expect(dataRows(file), hasLength(1));
      expect(columnValues(file, 'Supplier Name'), ['Kofi Mensah']);
      expect(columnValues(file, 'Product'), ['Cashew']);
    });

    test('suggests a file name describing the range', () {
      expect(
        service.suggestFileName(
          'Records',
          DateTime(2026, 1, 1),
          DateTime(2026, 9, 30),
        ),
        'Company_A_Records_2026-01-01_to_2026-09-30.xlsx',
      );
    });
  });

  group('Date filtering boundaries', () {
    test('includes a record on the first day of the range', () async {
      await addDelivery(
        id: 'on-start',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 1, 1, 8),
      );

      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 31),
      );

      expect(dataRows(file), hasLength(1));
    });

    test('includes a record late on the last day of the range', () async {
      await addDelivery(
        id: 'on-end',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 1, 31, 23, 59),
      );

      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 31),
      );

      // The end date is inclusive, so a record at 11:59pm on the final day must
      // still be exported.
      expect(dataRows(file), hasLength(1));
    });

    test('excludes a record one day after the range', () async {
      await addDelivery(
        id: 'just-after',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 2, 1, 0, 1),
      );

      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 31),
      );

      expect(dataRows(file), isEmpty);
    });

    test('filters on the record date, not on when the export runs', () async {
      await addDelivery(
        id: 'historical',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2020, 5, 4),
      );

      final file = await service.exportRange(
        DateTime(2100, 1, 1),
        DateTime(2100, 1, 2),
      );

      expect(dataRows(file), isEmpty);
    });
  });

  group('Product records export', () {
    test('exports only records for the requested product', () async {
      await addDelivery(
        id: 'cashew-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
        productId: 'PRD-CASHEW',
      );
      await addDelivery(
        id: 'cocoa-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 16),
        productId: 'PRD-COCOA',
        productName: 'Cocoa',
      );

      final file = await service.exportProductReport('PRD-CASHEW', 'Cashew');

      final ids = columnValues(file, 'Product ID');
      expect(ids, ['PRD-CASHEW']);
    });

    test('exports product records with no product filter', () async {
      await addDelivery(
        id: 'cashew-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
        productId: 'PRD-CASHEW',
      );
      await addDelivery(
        id: 'cocoa-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 16),
        productId: 'PRD-COCOA',
        productName: 'Cocoa',
      );

      final file = await service.exportProductReport('', '');

      expect(columnValues(file, 'Product ID').toSet(), {
        'PRD-CASHEW',
        'PRD-COCOA',
      });
    });
  });

  group('Supplier records export', () {
    test('exports only the selected supplier', () async {
      await addDelivery(
        id: 'kofi-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );
      await addDelivery(
        id: 'ama-row',
        supplier: supplier(id: 'SUP-002', name: 'Ama Owusu'),
        recordedAt: DateTime(2026, 3, 16),
      );

      final file = await service.exportSupplierRange(
        'SUP-001',
        'Kofi Mensah',
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(columnValues(file, 'Supplier ID'), ['SUP-001']);
      expect(columnValues(file, 'Supplier Name'), ['Kofi Mensah']);
    });

    test('combines several selected suppliers into one workbook', () async {
      await addDelivery(
        id: 'kofi-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );
      await addDelivery(
        id: 'ama-row',
        supplier: supplier(id: 'SUP-002', name: 'Ama Owusu'),
        recordedAt: DateTime(2026, 3, 16),
      );
      await addDelivery(
        id: 'other-row',
        supplier: supplier(id: 'SUP-003', name: 'Yaw Boateng'),
        recordedAt: DateTime(2026, 3, 17),
      );

      final file = await service.exportSuppliersRange(
        {'SUP-001': 'Kofi Mensah', 'SUP-002': 'Ama Owusu'},
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(columnValues(file, 'Supplier ID').toSet(), {'SUP-001', 'SUP-002'});
    });

    test('applies the date range to a supplier export', () async {
      await addDelivery(
        id: 'inside',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );
      await addDelivery(
        id: 'outside',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 9, 20),
      );

      final file = await service.exportSupplierRange(
        'SUP-001',
        'Kofi Mensah',
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 31),
      );

      expect(dataRows(file), hasLength(1));
    });
  });

  group('Company isolation', () {
    test("exports only the active company's records", () async {
      await addDelivery(
        id: 'company-a-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );

      // Record something in a different company.
      activeCompanyId = 'company-b';
      await addDelivery(
        id: 'company-b-row',
        supplier: supplier(id: 'SUP-900', name: 'Other Company Supplier'),
        recordedAt: DateTime(2026, 3, 15),
      );

      activeCompanyId = 'company-a';
      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(columnValues(file, 'Supplier Name'), ['Kofi Mensah']);
      expect(columnValues(file, 'Supplier ID'), isNot(contains('SUP-900')));
    });

    test('the other company sees none of it', () async {
      await addDelivery(
        id: 'company-a-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );

      activeCompanyId = 'company-b';
      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(dataRows(file), isEmpty);
    });

    test('a supplier export stays inside the active company', () async {
      await addDelivery(
        id: 'company-a-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );

      // The same supplier id exists in company B with different records.
      activeCompanyId = 'company-b';
      await addDelivery(
        id: 'company-b-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 20),
      );

      activeCompanyId = 'company-a';
      final file = await service.exportSupplierRange(
        'SUP-001',
        'Kofi Mensah',
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(dataRows(file), hasLength(1));
    });

    test('exports nothing when no company is active', () async {
      await addDelivery(
        id: 'company-a-row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );
      activeCompanyId = null;

      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      // With no company there is nothing to export, and it must never fall back
      // to reading every company's rows.
      expect(dataRows(file), isEmpty);
    });
  });

  group('Empty results', () {
    test('a range with no records still produces a usable workbook', () async {
      final file = await service.exportRange(
        DateTime(2030, 1, 1),
        DateTime(2030, 1, 31),
      );

      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
      // The header row survives, so the file is still a valid empty export.
      expect(dataRows(file), isEmpty);
      expect(receivingSheet(file).rows.length, 1);
    });

    test('an empty supplier selection writes no rows', () async {
      final file = await service.exportSuppliersRange(
        {},
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(dataRows(file), isEmpty);
    });
  });

  group('Save destination', () {
    test('writes into the folder the user chose', () async {
      await addDelivery(
        id: 'row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );
      final chosen = await Directory.systemTemp.createTemp(
        'excel-chosen-folder-',
      );
      addTearDown(() => chosen.delete(recursive: true));

      service.destinationPath = chosen.path;
      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(file.parent.path, chosen.path);
    });

    test('falls back to the default folder when nothing is chosen', () async {
      await addDelivery(
        id: 'row',
        supplier: supplier(id: 'SUP-001', name: 'Kofi Mensah'),
        recordedAt: DateTime(2026, 3, 15),
      );

      final file = await service.exportRange(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(file.parent.path, outputDirectory.path);
      expect(service.effectiveDestinationPath, 'the default folder');
    });

    test('reports a chosen folder that has since been removed', () async {
      final removed = await Directory.systemTemp.createTemp(
        'excel-removed-folder-',
      );
      await removed.delete(recursive: true);
      service.destinationPath = removed.path;

      await expectLater(
        service.exportRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no longer available'),
          ),
        ),
      );
    });
  });
}
