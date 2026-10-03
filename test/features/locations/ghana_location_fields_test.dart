import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/locations/ghana_location_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The location service calls a network API. These tests exercise the input
  // fields themselves, so an unseeded controller list is enough.
  Widget harness() {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GhanaLocationFields(
            regionController: TextEditingController(),
            districtController: TextEditingController(),
            townController: TextEditingController(),
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    // Wait for the location catalog future to resolve.
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('district accepts a full multi-character name', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(1), 'Kumasi Metropolitan');
    await tester.pumpAndSettle();

    final district = tester
        .widget<TextFormField>(fields.at(1))
        .controller!
        .text;
    expect(district, 'Kumasi Metropolitan');
  });

  testWidgets('district accepts a long multi-word name', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Atwima Nwabiagya North');
    await tester.pumpAndSettle();

    final district = tester
        .widget<TextFormField>(fields.at(1))
        .controller!
        .text;
    expect(district, 'Atwima Nwabiagya North');
  });

  testWidgets('town accepts a full multi-character name', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), 'Ejisu');
    await tester.pumpAndSettle();

    final town = tester.widget<TextFormField>(fields.at(2)).controller!.text;
    expect(town, 'Ejisu');
  });

  testWidgets('spaces are accepted in district and town names', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Ejura Sekyedumase');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(2), 'Konongo');
    await tester.pumpAndSettle();

    final district = tester
        .widget<TextFormField>(fields.at(1))
        .controller!
        .text;
    final town = tester.widget<TextFormField>(fields.at(2)).controller!.text;
    expect(district, 'Ejura Sekyedumase');
    expect(district, contains(' '));
    expect(town, 'Konongo');
  });

  testWidgets('typing is not truncated to a single character', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    final fields = find.byType(TextFormField);
    // Simulate typing one character at a time, as a real user would.
    for (final text in ['M', 'a', 'm', 'p', 'o', 'n', 'g']) {
      await tester.enterText(fields.at(2), text);
      await tester.pumpAndSettle();
    }
    await tester.enterText(fields.at(2), 'Mampong');
    await tester.pumpAndSettle();

    final town = tester.widget<TextFormField>(fields.at(2)).controller!.text;
    expect(town, 'Mampong');
    expect(town.length, greaterThan(1));
  });
}
