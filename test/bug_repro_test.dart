import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/locations/ghana_location_fields.dart';
import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_application_2/features/products/product_repository.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/receiving/receiving_service.dart';
import 'package:flutter_application_2/features/secretary/new_receiving_screen.dart';
import 'package:flutter_application_2/features/suppliers/supplier_form_screen.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Future<void> typeInto(
    WidgetTester tester,
    Finder field,
    String text,
  ) async {
    var typed = '';
    for (final ch in text.split('')) {
      typed += ch;
      await tester.enterText(field, typed);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('GhanaLocationFields char-by-char typing keeps every character',
      (tester) async {
    final town = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GhanaLocationFields(
              regionController: TextEditingController(),
              districtController: TextEditingController(),
              townController: town,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final field = find.byType(TextFormField).at(2);
    await typeInto(tester, field, 'Techiman');

    expect(town.text, 'Techiman');
    expect(tester.widget<TextFormField>(field).controller!.text, 'Techiman');
  });

  testWidgets('admin supplier form district accepts Techiman', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SupplierFormScreen(repository: SupplierRepository()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Order: name, phone, then Region, District, Town from GhanaLocationFields.
    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);
    final district = fields.at(3);
    await typeInto(tester, district, 'Techiman');

    expect(
      tester.widget<TextFormField>(district).controller!.text,
      'Techiman',
      reason: 'district truncated while typing in the admin form',
    );
  });

  testWidgets('secretary receiving form district accepts Techiman',
      (tester) async {
    sqfliteFfiInit();
    final database = await ProductDatabase.open(
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final suppliers = SupplierRepository(database: database);
    final products = ProductRepository(database);
    final deliveries = DeliveryRepository(database);
    final receiving = ReceivingService(
      database: database,
      supplierRepository: suppliers,
    );
    await suppliers.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: NewReceivingScreen(
          repository: suppliers,
          productRepository: products,
          deliveryRepository: deliveries,
          receivingService: receiving,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Region, District, Town are the three GhanaLocationFields TextFormField.
    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);
    final district = fields.at(1);
    await typeInto(tester, district, 'Techiman');

    expect(
      tester.widget<TextFormField>(district).controller!.text,
      'Techiman',
      reason: 'district truncated while typing in the secretary form',
    );
  });

  testWidgets('focus stays on the district field while typing', (tester) async {
    final district = TextEditingController();
    final town = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GhanaLocationFields(
              regionController: TextEditingController(),
              districtController: district,
              townController: town,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final field = find.byType(TextFormField).at(1);
    // Focus the field exactly once, then keep typing without re-focusing —
    // the same as a real user typing "Techiman" in one sitting.
    await tester.showKeyboard(field);
    const word = 'Techiman';
    for (var i = 1; i <= word.length; i++) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: word.substring(0, i),
          selection: TextSelection.collapsed(offset: i),
        ),
      );
      await tester.pump();
      final stillFocused = tester.widget<TextField>(
        find.descendant(of: field, matching: find.byType(TextField)),
      );
      expect(
        stillFocused.focusNode?.hasFocus,
        isTrue,
        reason: 'focus was lost after typing $i character(s)',
      );
    }
    await tester.pumpAndSettle();

    expect(district.text, 'Techiman');
  });
}
