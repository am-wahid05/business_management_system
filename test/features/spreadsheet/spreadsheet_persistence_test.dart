import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formula.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_clipboard.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_controller.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formatting.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Formatting, formulas and merged cells must all survive closing and reopening
/// the spreadsheet, and must never cross between companies.
void main() {
  late Database database;
  late DeliveryRepository deliveryRepository;
  late SupplierRepository supplierRepository;
  late ReceivingService receivingService;

  /// Opens the spreadsheet again over the same database, which is what closing
  /// and reopening the application does.
  SpreadsheetController openController({String? activeCompany = 'company-a'}) {
    return SpreadsheetController(
      SpreadsheetService(
        deliveryRepository: deliveryRepository,
        receivingService: receivingService,
        userIdProvider: () => 'user-1',
      ),
      stateStore: SpreadsheetStateStore(database),
      companyIdProvider: () => activeCompany,
    );
  }

  setUp(() async {
    sqfliteFfiInit();
    // The real production schema and migration path, so the v15 tables are
    // created exactly as they are on a real device.
    database = await ProductDatabase.open(databasePath: inMemoryDatabasePath);
    deliveryRepository = DeliveryRepository(
      database,
      companyIdProvider: () => 'company-a',
    );
    supplierRepository = SupplierRepository(
      database: database,
      companyIdProvider: () => 'company-a',
    );
    receivingService = ReceivingService(
      database: database,
      supplierRepository: supplierRepository,
      companyIdProvider: () => 'company-a',
      userIdProvider: () => 'user-1',
    );
  });

  tearDown(() => database.close());

  Future<void> seed(
    String id, {
    double weight = 80,
    String name = 'Ibrahim',
  }) async {
    await deliveryRepository.save(
      Delivery(
        id: id,
        supplier: Supplier(
          id: 'supplier-a',
          name: name,
          type: SupplierType.farmer,
          town: '',
          district: '',
          region: '',
          companyId: 'company-a',
        ),
        product: Product(id: 'cashew', name: 'Cashew'),
        recordedAt: DateTime(2026, 9, 20),
        bagWeights: [weight],
        recordedByUserId: 'user-1',
        companyId: 'company-a',
      ),
    );
  }

  group('formatting persists', () {
    test('a highlight survives reopening the spreadsheet', () async {
      await seed('d-1');
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(background: CellColor.yellow),
      );
      await first.saveState();

      // Reopen: a brand new controller over the same database.
      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));

      expect(second.formatAt(second.rows.first, 1).background, CellColor.yellow);
    });

    test('bold, italic and alignment survive reopening', () async {
      await seed('d-1');
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.formatRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
        (current) => current.copyWith(bold: true),
      );
      first.formatRange(
        const CellRange(startRow: 0, startColumn: 2, endRow: 0, endColumn: 2),
        (current) => current.copyWith(italic: true),
      );
      first.formatRange(
        const CellRange(startRow: 0, startColumn: 3, endRow: 0, endColumn: 3),
        (current) => current.copyWith(alignment: CellAlignment.center),
      );
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));
      final row = second.rows.first;

      expect(second.formatAt(row, 0).bold, isTrue);
      expect(second.formatAt(row, 2).italic, isTrue);
      expect(second.formatAt(row, 3).alignment, CellAlignment.center);
    });

    test('an unformatted cell keeps the default format', () async {
      await seed('d-1');
      final controller = openController();
      await controller.load(from: DateTime(2026), to: DateTime(2027));

      // Backward compatibility: a sheet saved before this change has no stored
      // format, and must fall back to the existing default.
      expect(controller.formatAt(controller.rows.first, 0).isPlain, isTrue);
    });

    test('an unchanged sheet is not rewritten', () async {
      await seed('d-1');
      final controller = openController();
      await controller.load(from: DateTime(2026), to: DateTime(2027));

      // Nothing changed, so there is nothing to save.
      expect(controller.hasStateChanges, isFalse);
      final before = await database.query('spreadsheet_cells');
      await controller.saveState();
      expect(await database.query('spreadsheet_cells'), before);
    });
  });

  group('formulas persist and recalculate', () {
    test('a SUM formula keeps its expression and result', () async {
      await seed('d-1', weight: 80);
      await seed('d-2', weight: 120);
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.setFormula(first.rows.last, 3, '=SUM(D1:D2)');
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));

      // The expression itself is restored.
      expect(second.formulaAt(second.rows.last, 3), '=SUM(D1:D2)');
      // And it recalculates to the correct value on load.
      expect(
        second.evaluateFormula(second.formulaAt(second.rows.last, 3)!).value,
        200,
      );
    });

    test('AVERAGE survives reopening', () async {
      await seed('d-1', weight: 80);
      await seed('d-2', weight: 120);
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.setFormula(first.rows.last, 3, '=AVERAGE(D1:D2)');
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));
      expect(
        second.evaluateFormula(second.formulaAt(second.rows.last, 3)!).value,
        100,
      );
    });

    test('COUNT, MIN and MAX survive reopening', () async {
      await seed('d-1', weight: 80);
      await seed('d-2', weight: 120);
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.setFormula(first.rows.first, 3, '=COUNT(D1:D2)');
      first.setFormula(first.rows.first, 2, '=MIN(D1:D2)');
      first.setFormula(first.rows.first, 1, '=MAX(D1:D2)');
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));
      final row = second.rows.first;
      expect(second.evaluateFormula(second.formulaAt(row, 3)!).value, 2);
      expect(second.evaluateFormula(second.formulaAt(row, 2)!).value, 80);
      expect(second.evaluateFormula(second.formulaAt(row, 1)!).value, 120);
    });

    test('an arithmetic formula survives reopening', () async {
      await seed('d-1', weight: 80);
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.setFormula(first.rows.first, 3, '=D1*2');
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));
      expect(
        second.evaluateFormula(second.formulaAt(second.rows.first, 3)!).value,
        160,
      );
    });

    test('a malformed formula produces the same error after reopening', () async {
      await seed('d-1');
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      first.setFormula(first.rows.first, 3, '=SUM(');
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));
      final result = second.evaluateFormula(
        second.formulaAt(second.rows.first, 3)!,
      );
      expect(result.isFailure, isTrue);
      expect(result.error, FormulaError.malformed);
    });

    test('a formula over a non-numeric cell keeps notANumber after reopening', () async {
      await seed('d-1', name: 'Ibrahim');
      await seed('d-2', name: 'Ama');
      final first = openController();
      await first.load(from: DateTime(2026), to: DateTime(2027));

      // D4 is a well formed reference to a cell that holds no number, so the
      // formula is syntactically valid but its operand is not a number.
      first.setFormula(first.rows.first, 3, '=D4');
      await first.saveState();

      final second = openController();
      await second.load(from: DateTime(2026), to: DateTime(2027));
      final result = second.evaluateFormula(
        second.formulaAt(second.rows.first, 3)!,
      );
      // The error survives the round trip, so a stored formula is not silently
      // re-evaluated into a value.
      expect(result.isFailure, isTrue);
      expect(result.error, FormulaError.notANumber);
    });

    test('a stored formula never becomes an official weight', () async {
      await seed('d-1', weight: 80);
      final controller = openController();
      await controller.load(from: DateTime(2026), to: DateTime(2027));

      controller.setFormula(controller.rows.first, 3, '=SUM(D1:D1)');
      await controller.saveState();

      // The stored presentation state has its own tables and cannot touch a
      // delivery, so the official weight is still the real bag weight.
      final saved = await deliveryRepository.findById('d-1');
      expect(saved!.bagWeights, [80]);
      expect(saved.totalWeight, 80);
      final formulaRows = await database.query('spreadsheet_formulas');
      expect(formulaRows.single['expression'], '=SUM(D1:D1)');
    });
  });

  group('company isolation', () {
    test('company B cannot see company A formatting', () async {
      await seed('d-1');
      final a = openController(activeCompany: 'company-a');
      await a.load(from: DateTime(2026), to: DateTime(2027));
      a.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(background: CellColor.red),
      );
      await a.saveState();

      final b = openController(activeCompany: 'company-b');
      await b.load(from: DateTime(2026), to: DateTime(2027));
      // The presentation state is scoped to Company B, so Company A's stored
      // format is never returned to it even though the fixture's repository
      // still reads Company A's rows.
      expect(b.formats, isEmpty);
      expect(
        b.formatAt(b.rows.first, 1).background,
        CellColor.none,
      );
    });

    test('company B cannot see company A formulas', () async {
      await seed('d-1');
      final a = openController(activeCompany: 'company-a');
      await a.load(from: DateTime(2026), to: DateTime(2027));
      a.setFormula(a.rows.first, 3, '=SUM(D1:D1)');
      await a.saveState();

      final b = openController(activeCompany: 'company-b');
      await b.load(from: DateTime(2026), to: DateTime(2027));
      expect(b.formulas, isEmpty);
    });

    test('saving company B does not change company A state', () async {
      await seed('d-1');
      final a = openController(activeCompany: 'company-a');
      await a.load(from: DateTime(2026), to: DateTime(2027));
      a.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(background: CellColor.green),
      );
      await a.saveState();

      final b = openController(activeCompany: 'company-b');
      await b.load(from: DateTime(2026), to: DateTime(2027));
      b.formatRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
        (current) => current.copyWith(bold: true),
      );
      await b.saveState();

      // Company A still has exactly its own row, untouched by Company B.
      final restored = openController(activeCompany: 'company-a');
      await restored.load(from: DateTime(2026), to: DateTime(2027));
      expect(restored.formats.length, 1);
      expect(
        restored.formatAt(restored.rows.first, 1).background,
        CellColor.green,
      );
    });

    test('switching back to company A restores its state', () async {
      await seed('d-1');
      final a = openController(activeCompany: 'company-a');
      await a.load(from: DateTime(2026), to: DateTime(2027));
      a.setFormula(a.rows.first, 3, '=D1*2');
      a.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(bold: true),
      );
      await a.saveState();

      // Visit company B, then come back.
      final b = openController(activeCompany: 'company-b');
      await b.load(from: DateTime(2026), to: DateTime(2027));

      final back = openController(activeCompany: 'company-a');
      await back.load(from: DateTime(2026), to: DateTime(2027));
      expect(back.formulaAt(back.rows.first, 3), '=D1*2');
      expect(back.formatAt(back.rows.first, 1).bold, isTrue);
    });
  });

  group('editing and deleting', () {
    test('a discarded draft does not leave orphaned state', () async {
      await seed('d-1');
      final controller = openController();
      await controller.load(from: DateTime(2026), to: DateTime(2027));

      final draft = controller.addDraft();
      controller.setFormula(draft, 3, '=SUM(D1:D1)');
      expect(controller.formulas.length, 1);

      controller.removeDraft(draft);
      expect(controller.formulas, isEmpty);
    });

    test('a new row keeps its formatting after being saved', () async {
      final controller = openController();
      await controller.load(from: DateTime(2026), to: DateTime(2027));

      final draft = controller.addDraft(date: DateTime(2026, 9, 20));
      controller.edit(
        draft,
        date: '20/09/2026',
        supplierName: 'New Supplier',
        productName: 'Cashew',
        weights: '90',
      );
      controller.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(background: CellColor.blue),
      );

      await controller.save();
      await controller.saveState();

      // The formatting followed the row onto its real delivery id.
      expect(controller.formats.length, 1);
      expect(
        controller.formatAt(controller.rows.first, 1).background,
        CellColor.blue,
      );
    });
  });
}
