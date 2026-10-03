import 'dart:io';

import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/exports/excel_export_service.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late Directory outputDirectory;
  late ExcelExportService service;

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
          recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL,
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
        },
      ),
    );
    outputDirectory = await Directory.systemTemp.createTemp(
      'albnc-export-test-',
    );
    service = ExcelExportService(
      DeliveryRepository(database),
      directoryProvider: () async => outputDirectory,
    );
  });

  tearDown(() async {
    await database.close();
    if (outputDirectory.existsSync()) {
      await outputDirectory.delete(recursive: true);
    }
  });

  test('exports a dated daily xlsx with detailed bag columns', () async {
    final supplier = Supplier(
      id: 'ALB-000001',
      name: 'Ibrahim Mensah',
      type: SupplierType.aggregator,
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
    );
    await service.deliveryRepository.save(
      Delivery(
        id: 'delivery-1',
        supplier: supplier,
        product: Product.cashew,
        recordedAt: DateTime(2026, 9, 20, 10),
        bagWeights: [82.5, 79.8],
        recordedByUserId: 'secretary',
      ),
    );

    final file = await service.exportDaily(DateTime(2026, 9, 20));

    expect(file.path, endsWith('Company_Daily_Report_2026-09-20.xlsx'));
    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(100));
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);
  });
}
