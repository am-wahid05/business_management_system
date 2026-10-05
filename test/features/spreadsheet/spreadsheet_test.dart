import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_clipboard.dart';
import 'package:flutter_application_2/features/imports/import_sheet_builder.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_controller.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_import_export.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_row.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_validation.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

Delivery _delivery({
  String id = 'd-1',
  String supplierName = 'Ibrahim Mensah',
  String supplierId = 'ALB-000001',
  String productId = 'cashew',
  double weight = 80,
  DateTime? recordedAt,
  String? recordedBy,
}) => Delivery(
  id: id,
  supplier: Supplier(
    id: supplierId,
    name: supplierName,
    type: SupplierType.farmer,
    town: 'Techiman',
    district: 'Techiman Municipal',
    region: 'Bono East',
  ),
  product: Product(id: productId, name: 'Cashew'),
  recordedAt: recordedAt ?? DateTime(2026, 9, 20),
  bagWeights: [weight],
  recordedByUserId: recordedBy,
);

Future<Database> _openDatabase() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
        CREATE TABLE deliveries (
          id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL,
          recorded_at TEXT NOT NULL, recorded_by_user_id TEXT, company_id TEXT,
          status TEXT NOT NULL, synchronization_status TEXT NOT NULL,
          supplier_internal_id TEXT, supplier_name TEXT NOT NULL,
          product_name TEXT NOT NULL, supplier_type TEXT NOT NULL,
          record_type TEXT NOT NULL DEFAULT 'individual',
          total_weight REAL, bag_count INTEGER, notes TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )''');
        await db.execute('''
        CREATE TABLE delivery_bag_weights (
          delivery_id TEXT NOT NULL, company_id TEXT, bag_number INTEGER NOT NULL,
          weight REAL NOT NULL, recorded_by_user_id TEXT,
          PRIMARY KEY (delivery_id, bag_number)
        )''');
        await db.execute('''
        CREATE TABLE suppliers (
          internal_id TEXT PRIMARY KEY, supplier_id TEXT NOT NULL UNIQUE,
          company_id TEXT, normalized_name TEXT NOT NULL, name TEXT NOT NULL,
          type TEXT NOT NULL, phone TEXT, town TEXT NOT NULL DEFAULT '',
          district TEXT NOT NULL DEFAULT '', region TEXT NOT NULL DEFAULT '',
          notes TEXT, is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          synchronization_status TEXT NOT NULL, synchronization_error TEXT
        )''');
        await db.execute(
          'CREATE TABLE local_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    ),
  );
}

void main() {
  late Database database;
  late DeliveryRepository deliveryRepository;
  late SupplierRepository supplierRepository;

  Future<SpreadsheetController> buildController({
    String? Function()? companyIdProvider,
    String? Function()? userIdProvider,
  }) async {
    deliveryRepository = DeliveryRepository(
      database,
      companyIdProvider: companyIdProvider,
      userIdProvider: userIdProvider,
    );
    supplierRepository = SupplierRepository(
      database: database,
      companyIdProvider: companyIdProvider,
    );
    return SpreadsheetController(
      SpreadsheetService(
        deliveryRepository: deliveryRepository,
        receivingService: ReceivingService(
          database: database,
          supplierRepository: supplierRepository,
          companyIdProvider: companyIdProvider,
          userIdProvider: userIdProvider,
        ),
        recorderNamesProvider: () async => const {'user-1': 'Ama'},
        catalogueProvider: () async => Product.initialProducts,
        userIdProvider: userIdProvider,
      ),
    );
  }

  setUp(() async {
    database = await _openDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  /// Every delivery the active company can see.
  Future<List<Delivery>> allDeliveries() =>
      deliveryRepository.forRange(DateTime(2000), DateTime(2100));

  group('row model', () {
    test('a draft row is new and reports the current date', () {
      final row = SpreadsheetRow.draft(date: DateTime(2026, 9, 26));
      expect(row.isNew, isTrue);
      expect(row.date, '26/09/2026');
      expect(row.state, SpreadsheetRowState.created);
    });

    test('a saved delivery becomes an unchanged row', () {
      final row = SpreadsheetRow.fromDelivery(
        _delivery(weight: 80),
        recorderName: 'Ama',
      );
      expect(row.isNew, isFalse);
      expect(row.state, SpreadsheetRowState.unchanged);
      expect(row.weights, '80');
      expect(row.totalWeight, 80);
      expect(row.numberOfBags, 1);
      expect(row.date, '20/09/2026');
    });

    test('a delivery with several bags reports them all', () {
      final delivery = Delivery(
        id: 'd-2',
        supplier: _delivery().supplier,
        product: _delivery().product,
        recordedAt: DateTime(2026, 9, 20),
        bagWeights: [50, 60, 70],
        recordedByUserId: 'u1',
      );
      final row = SpreadsheetRow.fromDelivery(delivery, recorderName: 'Ama');
      expect(row.weights, '50,60,70');
      expect(row.totalWeight, 180);
      expect(row.numberOfBags, 3);
    });

    test('editing a row marks it edited, and a new row stays new', () {
      final existing = SpreadsheetRow.fromDelivery(
        _delivery(),
        recorderName: 'Ama',
      );
      existing.markEdited();
      expect(existing.state, SpreadsheetRowState.edited);

      final draft = SpreadsheetRow.draft();
      draft.markEdited();
      expect(draft.state, SpreadsheetRowState.created);
    });

    test('an unparseable weight gives no total', () {
      final row = SpreadsheetRow.draft()
        ..weights = 'abc'
        ..supplierName = 'A'
        ..productName = 'Cashew'
        ..date = '26/09/2026';
      expect(row.parsedWeights, isNull);
      expect(row.totalWeight, isNull);
      expect(row.numberOfBags, isNull);
    });
  });

  group('validation', () {
    SpreadsheetRow validRow() =>
        SpreadsheetRow.draft(date: DateTime(2026, 9, 26))
          ..supplierName = 'John Mensah'
          ..productName = 'Cashew'
          ..weights = '50,60';

    test('a complete row is valid', () {
      expect(validateSpreadsheetRow(validRow()).isValid, isTrue);
    });

    test('a missing supplier is reported', () {
      final row = validRow()..supplierName = '';
      final check = validateSpreadsheetRow(row);
      expect(check.isValid, isFalse);
      expect(check.error, contains('Supplier'));
    });

    test('a missing product is reported', () {
      final row = validRow()..productName = '  ';
      expect(validateSpreadsheetRow(row).error, contains('Product'));
    });

    test('an invalid date is reported with the value', () {
      final row = validRow()..date = '31/02/2026';
      expect(validateSpreadsheetRow(row).error, contains('31/02/2026'));
    });

    test('a missing weight is reported', () {
      final row = validRow()..weights = '';
      expect(validateSpreadsheetRow(row).error, contains('bag weight'));
    });

    test('a zero or negative weight is rejected', () {
      expect(
        validateSpreadsheetRow(validRow()..weights = '0').isValid,
        isFalse,
      );
      expect(
        validateSpreadsheetRow(validRow()..weights = '-5').isValid,
        isFalse,
      );
    });

    test('thousands separated weights are accepted', () {
      final row = validRow()..weights = '1,200.5';
      expect(validateSpreadsheetRow(row).isValid, isTrue);
      expect(row.totalWeight, 1200.5);
    });

    test('applyRowValidation stores the message on the row', () {
      final row = validRow()..supplierName = '';
      applyRowValidation(row);
      expect(row.hasError, isTrue);
      expect(row.error, contains('Supplier'));
    });

    test('summariseRows counts each state', () {
      final rows = [
        SpreadsheetRow.fromDelivery(_delivery(), recorderName: 'Ama'),
        SpreadsheetRow.fromDelivery(_delivery(id: 'd-2'), recorderName: 'Ama')
          ..markEdited(),
        SpreadsheetRow.draft(),
      ];
      final summary = summariseRows(rows);
      expect(summary.unchanged, 1);
      expect(summary.edited, 1);
      expect(summary.created, 1);
      expect(summary.removed, 0);
    });
  });

  group('controller editing', () {
    test('adding a draft row appends an unsaved row', () async {
      final controller = await buildController();
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      expect(controller.rows, hasLength(1));
      expect(row.isNew, isTrue);
      expect(controller.hasChanges, isTrue);
    });

    test('editing a row marks it edited and revalidates', () async {
      final controller = await buildController();
      final row = controller.addDraft();
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
        date: '26/09/2026',
      );
      expect(row.state, SpreadsheetRowState.created);
      expect(row.hasError, isFalse);
      expect(row.totalWeight, 80);
    });

    test('a bad edit records a row level error', () async {
      final controller = await buildController();
      final row = controller.addDraft();
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
        date: '26/09/2026',
      );
      expect(row.hasError, isFalse);
      controller.edit(row, date: '31/02/2026');
      expect(row.hasError, isTrue);
      expect(row.error, contains('date'));
      expect(controller.errorCount, 1);
    });

    test('a draft row can be removed and restored', () async {
      final controller = await buildController();
      final row = controller.addDraft();
      expect(controller.removeDraft(row), isTrue);
      expect(row.isRemoved, isTrue);
      // A removed draft is not treated as a pending change.
      expect(controller.changedRows, isEmpty);
      expect(controller.restoreDraft(row), isTrue);
      expect(row.isRemoved, isFalse);
      expect(controller.changedRows, hasLength(1));
    });

    test('a saved record cannot be removed from the grid', () async {
      final controller = await buildController();
      await deliveryRepository.save(_delivery());
      await controller.load(from: DateTime(2026), to: DateTime(2027));
      expect(controller.rows, hasLength(1));
      expect(controller.removeDraft(controller.rows.single), isFalse);
      expect(controller.rows.single.isRemoved, isFalse);
    });

    test('discarding reloads and drops unsaved edits', () async {
      final controller = await buildController();
      await deliveryRepository.save(_delivery(weight: 80));
      await controller.load(from: DateTime(2026), to: DateTime(2027));
      final row = controller.rows.single;
      expect(row.weights, '80');

      controller.edit(row, weights: '999');
      expect(controller.hasChanges, isTrue);

      await controller.discard();
      expect(controller.hasChanges, isFalse);
      expect(controller.rows.single.weights, '80');
    });

    test('imported rows are added as unsaved drafts', () async {
      final controller = await buildController();
      final added = controller.addImportedRows([
        SpreadsheetRow(
          date: '26/09/2026',
          supplierName: 'John Mensah',
          productName: 'Cashew',
          weights: '80',
          recorderName: 'Ama',
          status: 'received',
        ),
      ]);
      expect(added, 1);
      expect(controller.rows.single.isNew, isTrue);
      expect(controller.hasChanges, isTrue);
      // Nothing has been written yet.
      expect(await allDeliveries(), isEmpty);
    });
  });

  group('saving through the existing services', () {
    test('a new row is created and the supplier matched', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '50,60',
      );

      final result = await controller.save();
      expect(result.created, 1);
      expect(result.failed, 0);
      expect(result.suppliersCreated, 1);

      final saved = await allDeliveries();
      expect(saved, hasLength(1));
      expect(saved.single.supplier.name, 'John Mensah');
      expect(saved.single.totalWeight, 110);
      expect(saved.single.bagWeights, [50, 60]);
      // The row now reflects the stored record.
      expect(row.isNew, isFalse);
      expect(row.state, SpreadsheetRowState.unchanged);
    });

    test('an edited row updates weights through the repository', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      await deliveryRepository.save(
        _delivery(weight: 80, recordedBy: 'user-1'),
      );
      await controller.load(from: DateTime(2026), to: DateTime(2027));
      final row = controller.rows.single;
      controller.edit(row, weights: '90,95');

      final result = await controller.save();
      expect(result.updated, 1);
      expect(result.created, 0);

      final saved = await deliveryRepository.findById('d-1');
      expect(saved!.bagWeights, [90, 95]);
      expect(saved.totalWeight, 185);
      // The recorder is preserved and the record is marked as corrected.
      expect(saved.recordedByUserId, 'user-1');
      expect(saved.status, DeliveryStatus.corrected);
    });

    test('unchanged rows are never written', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      await deliveryRepository.save(
        _delivery(weight: 80, recordedBy: 'user-1'),
      );
      await controller.load(from: DateTime(2026), to: DateTime(2027));

      final result = await controller.save();
      expect(result.unchanged, 1);
      expect(result.updated, 0);
      expect(result.created, 0);
      // The record is untouched.
      final saved = await deliveryRepository.findById('d-1');
      expect(saved!.bagWeights, [80]);
      expect(saved.status, DeliveryStatus.received);
    });

    test('duplicate protection skips a row that already exists', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      await deliveryRepository.save(
        _delivery(
          supplierName: 'John Mensah',
          supplierId: 'ALB-000009',
          weight: 80,
          recordedAt: DateTime(2026, 9, 26),
          recordedBy: 'user-1',
        ),
      );
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
      );

      final result = await controller.save();
      expect(result.skippedDuplicates, 1);
      expect(result.created, 0);
      // The existing record was not duplicated or overwritten.
      expect(await allDeliveries(), hasLength(1));
    });

    test('a row with an error is rejected and reported', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
        date: '31/02/2026',
      );

      final result = await controller.save();
      expect(result.failed, 1);
      expect(result.created, 0);
      expect(result.errors, isNotEmpty);
      expect(await allDeliveries(), isEmpty);
    });

    test('the recorder is the signed in user, never another one', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
      );
      await controller.save();

      final saved = await allDeliveries();
      expect(saved.single.recordedByUserId, 'user-1');
    });

    test('a row cannot be written to another company', () async {
      String? active = 'company-1';
      final controller = await buildController(
        companyIdProvider: () => active,
        userIdProvider: () => 'user-1',
      );
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
      );
      await controller.save();
      expect((await allDeliveries()).single.companyId, 'company-1');

      // Another company sees none of it.
      active = 'company-2';
      await controller.load(from: DateTime(2026), to: DateTime(2027));
      expect(controller.rows, isEmpty);
    });

    test('saving is blocked when no company is active', () async {
      final controller = await buildController(
        companyIdProvider: () => null,
        userIdProvider: () => 'user-1',
      );
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
      );
      final result = await controller.save();
      expect(result.created, 0);
      expect(result.failed, 1);
      expect(await allDeliveries(), isEmpty);
    });
  });

  group('import and export reuse the Excel reader', () {
    test('a sheet is read into editable rows', () {
      final sheet = buildImportSheetFromCsv(
        'Date,Supplier Name,Product,Total Weight\n'
        '26/09/2026,John Mensah,Cashew,80\n'
        '05/09/2026,Ama Serwa,Cocoa,"1,200.5"\n',
      )!;
      final rows = spreadsheetRowsFromSheet(sheet);
      expect(rows, hasLength(2));
      expect(rows[0].date, '26/09/2026');
      expect(rows[0].supplierName, 'John Mensah');
      expect(rows[0].productName, 'Cashew');
      expect(rows[0].weights, '80');
      expect(rows[1].weights, '1,200.5');
      // Every imported row is a new draft, not a saved record.
      expect(rows.every((row) => row.isNew), isTrue);
    });

    test('import then edit then save stores the corrected value', () async {
      final controller = await buildController(userIdProvider: () => 'user-1');
      final sheet = buildImportSheetFromCsv(
        'Date,Supplier Name,Product,Total Weight\n'
        '26/09/2026,John Mensah,Cashew,80\n',
      )!;
      controller.addImportedRows(spreadsheetRowsFromSheet(sheet));
      // Nothing is written during the preview.
      expect(await allDeliveries(), isEmpty);

      controller.edit(controller.rows.single, weights: '81');
      final result = await controller.save();
      expect(result.created, 1);
      expect((await allDeliveries()).single.totalWeight, 81);
    });

    test('grid rows export to a sheet the reader understands', () {
      final rows = [
        SpreadsheetRow.fromDelivery(_delivery(weight: 80), recorderName: 'Ama'),
      ];
      final sheet = spreadsheetSheetFromRows(rows)!;
      expect(sheet.headers, contains('Date'));
      expect(sheet.headers, contains('Supplier Name'));
      expect(sheet.headers, contains('Total Weight'));
      expect(sheet.rows, hasLength(1));

      // The exported sheet is read back by the same reader.
      final reread = spreadsheetRowsFromSheet(sheet);
      expect(reread, hasLength(1));
      expect(reread.first.supplierName, 'Ibrahim Mensah');
      expect(reread.first.date, '20/09/2026');
      expect(reread.first.weights, '80');
    });

    test('removed rows are left out of the export', () {
      final draft = SpreadsheetRow.draft(date: DateTime(2026, 9, 26))
        ..supplierName = 'A'
        ..productName = 'Cashew'
        ..weights = '80'
        ..state = SpreadsheetRowState.deleted;
      final rows = [
        SpreadsheetRow.fromDelivery(_delivery(), recorderName: 'Ama'),
        draft,
      ];

      final sheet = spreadsheetSheetFromRows(rows)!;
      expect(sheet.rows, hasLength(1));
    });
  });

  group('unlimited rows', () {
    test('rows can be added without an artificial limit', () async {
      final controller = await buildController();
      for (var index = 0; index < 2000; index++) {
        controller.addDraft();
      }
      expect(controller.rows, hasLength(2000));
    });
  });

  group('copy and paste', () {
    test('a single cell copies and pastes', () async {
      final controller = await buildController();
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
      );
      final second = controller.addDraft();

      controller.copy(const CellRange.single(1, 0));
      final pasted = controller.paste(
        const CellRange(startColumn: 1, startRow: 1, endColumn: 1, endRow: 1),
      );
      expect(pasted, 1);
      expect(second.supplierName, 'John Mensah');
    });

    test('an entire row copies and pastes', () async {
      final controller = await buildController();
      final row = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        row,
        supplierName: 'John Mensah',
        productName: 'Cocoa',
        weights: '50,60',
      );
      final second = controller.addDraft();

      controller.copy(
        const CellRange(startColumn: 0, startRow: 0, endColumn: 3, endRow: 0),
      );
      controller.paste(
        const CellRange(startColumn: 0, startRow: 1, endColumn: 3, endRow: 1),
      );
      expect(second.date, row.date);
      expect(second.supplierName, 'John Mensah');
      expect(second.productName, 'Cocoa');
      expect(second.weights, '50,60');
    });

    test('a single value repeats down many rows', () async {
      final controller = await buildController();
      final first = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(first, supplierName: 'John Mensah');
      for (var index = 0; index < 20; index++) {
        controller.addDraft();
      }

      controller.copy(const CellRange.single(1, 0));
      final pasted = controller.paste(
        const CellRange(startColumn: 1, startRow: 0, endColumn: 1, endRow: 20),
      );
      expect(pasted, 21);
      expect(
        controller.rows.every((row) => row.supplierName == 'John Mensah'),
        isTrue,
      );
    });

    test('pasted values are revalidated', () async {
      final controller = await buildController();
      final first = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(
        first,
        supplierName: 'John Mensah',
        productName: 'Cashew',
        weights: '80',
      );
      controller.setCell(controller.rows.first, 0, '31/02/2026');
      final second = controller.addDraft();
      controller.copy(const CellRange.single(0, 0));
      controller.paste(
        const CellRange(startColumn: 0, startRow: 1, endColumn: 0, endRow: 1),
      );
      expect(second.hasError, isTrue);
      expect(second.error, contains('31/02/2026'));
    });

    test('pasting into rows that do not exist yet creates them', () async {
      final controller = await buildController();
      final first = controller.addDraft(date: DateTime(2026, 9, 26));
      controller.edit(first, supplierName: 'John Mensah');
      controller.copy(const CellRange.single(1, 0));
      final pasted = controller.paste(
        const CellRange(startColumn: 1, startRow: 1, endColumn: 1, endRow: 4),
      );
      expect(pasted, 4);
      expect(controller.rows, hasLength(5));
    });

    test('pasting with nothing copied does nothing', () async {
      final controller = await buildController();
      controller.addDraft();
      expect(controller.paste(const CellRange.single(0, 0)), 0);
    });
  });
}
