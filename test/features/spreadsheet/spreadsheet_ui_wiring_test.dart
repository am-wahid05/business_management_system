import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_clipboard.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_controller.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_formatting.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_merges.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_service.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_state_store.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The UI drives the same controller methods the buttons call, so these cover the
/// screen's wiring to the persistent state without standing up a widget tree.
void main() {
  late Database database;
  late DeliveryRepository deliveryRepository;
  late SupplierRepository supplierRepository;
  late ReceivingService receivingService;

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

  Future<void> seed(String id, {double weight = 80}) async {
    await deliveryRepository.save(
      Delivery(
        id: id,
        supplier: Supplier(
          id: 'supplier-a',
          name: 'Ibrahim',
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

  group('formatting applied through the UI persists', () {
    test('a highlight applied, saved and reopened is still there', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));

      // What the Format button does for the selected range.
      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(background: CellColor.yellow),
      );
      // The user sees it immediately, before any save.
      expect(sheet.formatAt(sheet.rows.first, 1).background, CellColor.yellow);
      await sheet.saveState();

      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      expect(
        reopened.formatAt(reopened.rows.first, 1).background,
        CellColor.yellow,
      );
    });

    test('bold, italic, text colour and alignment all persist', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      final row = sheet.rows.first;

      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
        (current) => current.copyWith(bold: true),
      );
      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
        (current) => current.copyWith(italic: true, text: CellColor.red),
      );
      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 2, endRow: 0, endColumn: 2),
        (current) => current.copyWith(alignment: CellAlignment.right),
      );
      await sheet.saveState();

      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      final restored = reopened.rows.first;
      expect(reopened.formatAt(restored, 0).bold, isTrue);
      expect(reopened.formatAt(restored, 1).italic, isTrue);
      expect(reopened.formatAt(restored, 1).text, CellColor.red);
      expect(reopened.formatAt(restored, 2).alignment, CellAlignment.right);
      expect(row, isNotNull);
    });

    test('clearing formatting removes it after reopening', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
        (current) => current.copyWith(bold: true),
      );
      await sheet.saveState();

      // The "Clear formatting" menu item.
      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
        (_) => const CellFormat(),
      );
      await sheet.saveState();

      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      expect(reopened.formatAt(reopened.rows.first, 0).isPlain, isTrue);
    });
  });

  group('formulas applied through the UI persist and recalculate', () {
    test('a formula entered, saved and reopened still calculates', () async {
      await seed('d-1', weight: 80);
      await seed('d-2', weight: 120);
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));

      // What the Formula button's Apply does for the selected cell.
      sheet.setFormula(sheet.rows.last, 3, '=SUM(D1:D2)');
      // The live preview the dialog shows uses this same evaluator.
      expect(sheet.formulaDisplay('=SUM(D1:D2)'), '200');
      await sheet.saveState();

      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      final expression = reopened.formulaAt(reopened.rows.last, 3);
      expect(expression, '=SUM(D1:D2)');
      // Recalculated on load, not read from a stored result.
      expect(reopened.evaluateFormula(expression!).value, 200);
    });

    test('clearing a formula removes it after reopening', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      sheet.setFormula(sheet.rows.first, 3, '=D1*2');
      await sheet.saveState();

      // The dialog's Clear action sends an empty expression.
      sheet.setFormula(sheet.rows.first, 3, '');
      await sheet.saveState();

      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      expect(reopened.formulaAt(reopened.rows.first, 3), isNull);
    });

    test('a formula never becomes a delivery weight', () async {
      await seed('d-1', weight: 80);
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));

      sheet.setFormula(sheet.rows.first, 3, '=SUM(D1:D1)');
      await sheet.saveState();

      // The row still holds the real bag weight, and the formula lives only in
      // the presentation tables.
      final saved = await deliveryRepository.findById('d-1');
      expect(saved!.bagWeights, [80]);
      expect(saved.totalWeight, 80);
      expect((await database.query('spreadsheet_formulas')).length, 1);
      expect((await database.query('delivery_bag_weights')).length, 1);
    });
  });

  group('merges applied through the UI persist', () {
    test('a merge applied, saved and reopened is still merged', () async {
      await seed('d-1');
      await seed('d-2');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));

      // What the Merge button does for the selected range.
      final merged = sheet.mergeRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 2),
      );
      expect(merged.isSuccess, isTrue);
      await sheet.saveState();

      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      expect(reopened.merges.merges.length, 1);
      expect(reopened.merges.merges.single.endColumn, 2);
    });

    test('unmerging, saving and reopening leaves it unmerged', () async {
      await seed('d-1');
      await seed('d-2');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      sheet.mergeRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 1),
      );
      await sheet.saveState();

      // Reopen, unmerge, save.
      final reopened = openController();
      await reopened.load(from: DateTime(2026), to: DateTime(2027));
      final result = reopened.unmergeRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 1),
      );
      expect(result.isSuccess, isTrue);
      await reopened.saveState();

      final again = openController();
      await again.load(from: DateTime(2026), to: DateTime(2027));
      expect(again.merges.merges, isEmpty);
    });

    test(
      'an invalid merge reports the existing message and changes nothing',
      () async {
        await seed('d-1');
        await seed('d-2');
        final sheet = openController();
        await sheet.load(from: DateTime(2026), to: DateTime(2027));

        sheet.mergeRange(
          const CellRange(startRow: 0, startColumn: 0, endRow: 1, endColumn: 1),
        );
        final before = sheet.merges.merges.length;

        // An overlapping merge is refused and the message reaches the UI.
        final result = sheet.mergeRange(
          const CellRange(startRow: 1, startColumn: 1, endRow: 1, endColumn: 3),
        );
        expect(result.isSuccess, isFalse);
        expect(result.failure, MergeFailure.overlapsExisting);
        expect(result.message, isNotNull);
        expect(sheet.merges.merges.length, before);
      },
    );

    test('merges stay company isolated through the UI path', () async {
      await seed('d-1');
      final a = openController(activeCompany: 'company-a');
      await a.load(from: DateTime(2026), to: DateTime(2027));
      a.mergeRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 1),
      );
      await a.saveState();

      final b = openController(activeCompany: 'company-b');
      await b.load(from: DateTime(2026), to: DateTime(2027));
      expect(b.merges.merges, isEmpty);
    });
  });

  group('dirty and save state', () {
    test('a freshly loaded sheet is not dirty', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      expect(sheet.hasStateChanges, isFalse);
      expect(sheet.hasChanges, isFalse);
    });

    test('formatting makes the sheet dirty and saving clears it', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      expect(sheet.hasStateChanges, isFalse);

      sheet.formatRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
        (current) => current.copyWith(bold: true),
      );
      // The Save button is now meaningful even though no row data changed.
      expect(sheet.hasStateChanges, isTrue);
      expect(sheet.hasChanges, isFalse);

      await sheet.save();
      expect(sheet.hasStateChanges, isFalse);
    });

    test('a formula makes the sheet dirty and saving clears it', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));

      sheet.setFormula(sheet.rows.first, 3, '=D1*2');
      expect(sheet.hasStateChanges, isTrue);
      await sheet.save();
      expect(sheet.hasStateChanges, isFalse);
    });

    test('a merge makes the sheet dirty and saving clears it', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));

      sheet.mergeRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 1),
      );
      expect(sheet.hasStateChanges, isTrue);
      await sheet.save();
      expect(sheet.hasStateChanges, isFalse);
    });

    test('a refused merge does not make the sheet dirty', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      await sheet.save();
      expect(sheet.hasStateChanges, isFalse);

      // A single cell is refused, so nothing changed and nothing needs saving.
      final result = sheet.mergeRange(
        const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
      );
      expect(result.isSuccess, isFalse);
      expect(sheet.hasStateChanges, isFalse);
    });

    test('editing is in memory until Save, with no write per change', () async {
      await seed('d-1');
      final sheet = openController();
      await sheet.load(from: DateTime(2026), to: DateTime(2027));
      final before = await database.query('spreadsheet_cells');

      // Several formatting taps, exactly as tapping the Format button repeatedly.
      for (final colour in [
        CellColor.yellow,
        CellColor.green,
        CellColor.blue,
      ]) {
        sheet.formatRange(
          const CellRange(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
          (current) => current.copyWith(background: colour),
        );
      }
      // Nothing has been written to the database yet.
      expect(await database.query('spreadsheet_cells'), before);

      await sheet.saveState();
      final after = await database.query('spreadsheet_cells');
      expect(after.length, 1);
      expect(after.single['background'], 'blue');
    });
  });
}
