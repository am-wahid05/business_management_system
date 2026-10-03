import 'package:flutter/material.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/imports/excel_import_service.dart';
import 'package:flutter_application_2/features/imports/excel_cell_parser.dart';
import 'package:flutter_application_2/features/imports/supplier_import_dialog.dart';
import 'package:flutter_application_2/features/imports/workbook_grid_model.dart';
import 'package:flutter_application_2/features/imports/workbook_grid_store.dart';
import 'package:flutter_application_2/features/exports/excel_export_service.dart';
import 'package:flutter_application_2/features/management/workbook_grid_screen.dart';
import 'package:flutter_application_2/features/management/excel_export_screen.dart';
import 'package:flutter_application_2/features/management/suppliers_screen.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(':memory:');
    await database.execute('''
      CREATE TABLE suppliers (
        internal_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        company_id TEXT,
        normalized_name TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        phone TEXT,
        town TEXT NOT NULL,
        district TEXT NOT NULL,
        region TEXT NOT NULL,
        notes TEXT,
        is_active INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synchronization_status TEXT NOT NULL,
        UNIQUE(company_id, supplier_id),
        UNIQUE(company_id, normalized_name)
      )
    ''');
  });

  tearDown(() async => database.close());

  test(
    'imports selected names atomically as persistent active farmers',
    () async {
      final repository = SupplierRepository(
        database: database,
        companyIdProvider: () => 'company-a',
        now: () => DateTime(2026, 9, 30, 12),
      );
      await repository.initialize();

      final result = await repository.importNames([
        '  Kwame   Farms  ',
        'kwame farms',
        '',
      ]);

      expect(result.created, hasLength(1));
      expect(result.created.single.name, 'Kwame Farms');
      expect(result.created.single.type, SupplierType.farmer);
      expect(result.created.single.phone, isNull);
      expect(result.created.single.town, isEmpty);
      expect(result.created.single.district, isEmpty);
      expect(result.created.single.region, isEmpty);
      expect(result.created.single.notes, isNull);
      expect(result.created.single.isActive, isTrue);
      expect(result.created.single.companyId, 'company-a');
      expect(result.duplicates, 1);
      expect(result.skipped, 1);

      final reloaded = SupplierRepository(
        database: database,
        companyIdProvider: () => 'company-a',
      );
      await reloaded.initialize();
      expect(reloaded.suppliers, hasLength(1));
      expect(reloaded.suppliers.single.id, result.created.single.id);
      expect(reloaded.suppliers.single.createdAt, DateTime(2026, 9, 30, 12));
    },
  );

  test(
    'existing names are company-scoped and cannot be edited across companies',
    () async {
      var activeCompany = 'company-a';
      final repository = SupplierRepository(
        database: database,
        companyIdProvider: () => activeCompany,
      );
      final companyAResult = await repository.importNames(['Supplier One']);
      final companyASupplier = companyAResult.created.single;

      activeCompany = 'company-b';
      await repository.initialize();
      expect(repository.suppliers, isEmpty);
      final companyBResult = await repository.importNames([
        'Supplier Two',
        ' supplier one ',
      ]);
      expect(companyBResult.created, hasLength(2));
      expect(companyBResult.alreadyExisted, 0);
      expect(
        repository.suppliers.map((supplier) => supplier.name),
        containsAll(['Supplier Two', 'supplier one']),
      );

      await expectLater(
        repository.update(companyASupplier.copyWith(name: 'Changed by B')),
        throwsStateError,
      );
      await expectLater(
        repository.setActive(companyASupplier.id, false),
        throwsStateError,
      );

      activeCompany = 'company-a';
      await repository.initialize();
      expect(repository.suppliers.map((supplier) => supplier.name), [
        'Supplier One',
      ]);
      final repeated = await repository.importNames([' supplier one ']);
      expect(repeated.created, isEmpty);
      expect(repeated.alreadyExisted, 1);
    },
  );

  test(
    'does not persist any name if a row makes the transaction fail',
    () async {
      await database.execute('''
      CREATE TRIGGER reject_supplier BEFORE INSERT ON suppliers
      WHEN NEW.name = 'Fail Supplier'
      BEGIN SELECT RAISE(ABORT, 'forced supplier import failure'); END
    ''');
      final repository = SupplierRepository(
        database: database,
        companyIdProvider: () => 'company-a',
      );

      await expectLater(
        repository.importNames(['First Supplier', 'Fail Supplier']),
        throwsA(isA<Exception>()),
      );
      expect(repository.suppliers, isEmpty);
      expect(
        await database.query(
          'suppliers',
          where: 'company_id = ?',
          whereArgs: ['company-a'],
        ),
        isEmpty,
      );
    },
  );

  test('a scoped import stops when no active company is present', () async {
    final repository = SupplierRepository(
      database: database,
      companyIdProvider: () => null,
    );

    await expectLater(
      repository.importNames(['Supplier One']),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Supplier import requires an active company'),
        ),
      ),
    );
    expect(await database.query('suppliers'), isEmpty);
  });

  test('unscoped local demo imports preserve a null company id', () async {
    final repository = SupplierRepository(database: database);
    final result = await repository.importNames(['Demo Supplier']);

    expect(result.created.single.companyId, isNull);
    expect(await database.query('suppliers'), hasLength(1));
    expect((await database.query('suppliers')).single['company_id'], isNull);
  });

  testWidgets(
    'preview is read-only until confirmation and separates duplicates/existing',
    (tester) async {
      final repository = SupplierRepository(
        companyIdProvider: () => 'company-a',
      );
      await repository.create(
        name: 'Existing Supplier Ltd',
        type: SupplierType.aggregator,
        phone: '',
        town: '',
        district: '',
        region: '',
        notes: '',
      );
      final book = WorkbookGridBook(
        filename: 'accounts.xlsx',
        sheets: [
          WorkbookGrid(
            name: 'Suppliers',
            cells: [
              [const ParsedCell(text: 'Supplier Name')],
              [const ParsedCell(text: 'Kwame Farms')],
              [const ParsedCell(text: ' kwame   farms ')],
              [const ParsedCell(text: 'Existing Supplier Ltd')],
              [const ParsedCell.blank()],
              [const ParsedCell(text: 'Total')],
              [const ParsedCell(text: '=D1:A2', isFormula: true)],
            ],
          ),
        ],
      );

      Future<SupplierBulkImportResult?>? importFuture;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  importFuture = showDialog<SupplierBulkImportResult>(
                    context: context,
                    builder: (_) => SupplierImportDialog(
                      book: book,
                      repository: repository,
                    ),
                  );
                },
                child: const Text('Open preview'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open preview'));
      await _settleUi(tester);

      expect(find.text('Supplier column'), findsOneWidget);
      expect(find.text('New suppliers: 1'), findsOneWidget);
      expect(find.text('Already existing: 1'), findsOneWidget);
      expect(find.text('Duplicates in workbook: 1'), findsOneWidget);
      expect(find.text('Ignored rows: 4'), findsOneWidget);
      expect(find.text('=D1:A2'), findsNothing);
      expect(find.text('Kwame Farms'), findsOneWidget);
      expect(find.text('Existing Supplier Ltd'), findsOneWidget);
      expect(repository.suppliers, hasLength(1));

      await tester.tap(find.text('Import Selected'));
      await _settleUi(tester);
      final result = await importFuture;
      expect(result!.createdCount, 1);
      expect(repository.suppliers, hasLength(2));
      expect(
        repository.findById(result.created.single.id)!.type,
        SupplierType.farmer,
      );
      expect(
        repository.findById(result.created.single.id)!.companyId,
        'company-a',
      );
    },
  );

  testWidgets('Suppliers screen refreshes when the import repository changes', (
    tester,
  ) async {
    final repository = SupplierRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SuppliersScreen(
          repository: repository,
          deliveryRepository: DeliveryRepository(database),
          onLogout: () {},
        ),
      ),
    );
    await _settleUi(tester);
    expect(find.text('No suppliers found.'), findsOneWidget);

    await repository.importNames(['Fresh Farmer']);
    await _settleUi(tester);
    expect(find.text('Fresh Farmer'), findsOneWidget);
  });

  testWidgets('manual column selection skips a generic heading row', (
    tester,
  ) async {
    final repository = SupplierRepository(
      companyIdProvider: () => 'company-a',
    );
    final book = WorkbookGridBook(
      filename: 'manual.xlsx',
      sheets: [
        WorkbookGrid(
          name: 'Sheet1',
          cells: [
            [const ParsedCell(text: 'Alpha'), const ParsedCell(text: 'Beta')],
            [
              const ParsedCell(text: 'Kofi Farms'),
              const ParsedCell(text: 'Ama Trading'),
            ],
          ],
        ),
      ],
    );
    await _showDialog(tester, book, repository);

    expect(find.text('Select a column'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('supplier-import-column')));
    await _settleUi(tester);
    await tester.tap(find.text('B · Beta').last);
    await _settleUi(tester);

    expect(find.text('Ama Trading'), findsOneWidget);
    expect(find.text('Kofi Farms'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await _settleUi(tester);
  });

  testWidgets('multiple sheets can be selected in the import preview', (
    tester,
  ) async {
    final repository = SupplierRepository(
      companyIdProvider: () => 'company-a',
    );
    final book = WorkbookGridBook(
      filename: 'multi.xlsx',
      sheets: [
        WorkbookGrid(
          name: 'Summary',
          cells: [
            [const ParsedCell(text: 'Title')],
            [const ParsedCell(text: 'Numbers')],
          ],
        ),
        WorkbookGrid(
          name: 'Supplier List',
          cells: [
            [const ParsedCell(text: 'Supplier Name')],
            [const ParsedCell(text: 'Abena Trading')],
          ],
        ),
      ],
    );
    await _showDialog(tester, book, repository);

    await tester.tap(find.byKey(const ValueKey('supplier-import-sheet')));
    await _settleUi(tester);
    await tester.tap(find.text('Supplier List').last);
    await _settleUi(tester);

    expect(find.text('Abena Trading'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settleUi(tester);
  });

  testWidgets('import preview shows the active-company requirement', (
    tester,
  ) async {
    final repository = SupplierRepository(
      companyIdProvider: () => null,
    );
    final book = WorkbookGridBook(
      filename: 'accounts.xlsx',
      sheets: [
        WorkbookGrid(
          name: 'Suppliers',
          cells: [
            [const ParsedCell(text: 'Supplier Name')],
            [const ParsedCell(text: 'Supplier One')],
          ],
        ),
      ],
    );
    await _showDialog(tester, book, repository);

    expect(
      find.text('Supplier import requires an active company.'),
      findsOneWidget,
    );
    expect(find.text('Import Selected'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await _settleUi(tester);
  });

  testWidgets(
    'grid import action is admin-only and belongs to the workbook grid',
    (tester) async {
      final service = ExcelImportService(
        database: database,
        deliveryRepository: DeliveryRepository(database),
        userId: 'admin-1',
      );
      final book = WorkbookGridBook(
        filename: 'accounts.xlsx',
        sheets: [
          WorkbookGrid(
            name: 'Suppliers',
            cells: [
              [const ParsedCell(text: 'Supplier Name')],
              [const ParsedCell(text: 'Supplier One')],
            ],
          ),
        ],
      );

      final repository = SupplierRepository(
        companyIdProvider: () => 'company-a',
      );
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: WorkbookGridScreen(
            service: service,
            store: const WorkbookGridStore(null),
            currentUser: () => AppUser(
              id: 'admin-1',
              username: 'admin',
              displayName: 'Admin',
              role: UserRole.admin,
              isActive: true,
              companyId: 'company-a',
            ),
            initialBook: book,
            supplierRepository: repository,
          ),
        ),
      );
      await _settleUi(tester);
      expect(
        find.byKey(const ValueKey('import-suppliers-action')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('import-suppliers-action')));
      await _settleUi(tester);
      expect(find.text('Supplier One'), findsOneWidget);
      expect(repository.suppliers, isEmpty);
      await tester.tap(find.text('Import Selected'));
      await _settleUi(tester);
      expect(find.textContaining('Supplier import complete'), findsOneWidget);
      expect(repository.suppliers, hasLength(1));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: WorkbookGridScreen(
            service: service,
            store: const WorkbookGridStore(null),
            currentUser: () => AppUser(
              id: 'secretary-1',
              username: 'secretary',
              displayName: 'Secretary',
              role: UserRole.secretary,
              isActive: true,
              companyId: 'company-a',
            ),
            initialBook: book,
          ),
        ),
      );
      await _settleUi(tester);
      expect(
        find.byKey(const ValueKey('import-suppliers-action')),
        findsNothing,
      );
      expect(find.text('Import Suppliers'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ExcelExportScreen(
            service: ExcelExportService(DeliveryRepository(database)),
          ),
        ),
      );
      await _settleUi(tester);
      expect(find.text('Excel Export'), findsOneWidget);
      expect(find.text('Import Suppliers'), findsNothing);
    },
  );
}

Future<void> _showDialog(
  WidgetTester tester,
  WorkbookGridBook book,
  SupplierRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<SupplierBulkImportResult>(
              context: context,
              builder: (_) =>
                  SupplierImportDialog(book: book, repository: repository),
            ),
            child: const Text('Open preview'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open preview'));
  await _settleUi(tester);
}

/// Pumps dialog transitions without waiting forever on an in-progress spinner.
Future<void> _settleUi(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
}
