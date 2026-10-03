import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/reports/daily_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late DeliveryRepository deliveryRepository;
  late DailyReportRepository reportRepository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(':memory:', options: OpenDatabaseOptions(
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE deliveries (
            id TEXT PRIMARY KEY,
            supplier_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            recorded_by_user_id TEXT NOT NULL,
            status TEXT NOT NULL,
            synchronization_status TEXT NOT NULL,
            supplier_name TEXT NOT NULL,
            product_name TEXT NOT NULL,
            supplier_type TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE delivery_bag_weights (
            delivery_id TEXT NOT NULL,
            bag_number INTEGER NOT NULL,
            weight REAL NOT NULL,
            PRIMARY KEY (delivery_id, bag_number)
          )
        ''');
      },
    ));
    deliveryRepository = DeliveryRepository(database);
    reportRepository = DailyReportRepository(deliveryRepository);
  });

  tearDown(() => database.close());

  test('generates daily totals and product totals from stored deliveries', () async {
    final date = DateTime(2026, 9, 20);
    final ibrahim = Supplier(id: 'ALB-000001', name: 'Ibrahim Mensah', type: SupplierType.aggregator, town: 'Techiman', district: 'Techiman Municipal', region: 'Bono East');
    final kwame = Supplier(id: 'ALB-000002', name: 'Kwame Boateng', type: SupplierType.farmer, town: 'Kintampo', district: 'Kintampo Municipal', region: 'Bono East');

    await deliveryRepository.save(Delivery(id: 'one', supplier: ibrahim, product: Product.cashew, recordedAt: date.add(const Duration(hours: 8)), bagWeights: [82.5, 79.8, 81.2], recordedByUserId: 'secretary'));
    await deliveryRepository.save(Delivery(id: 'two', supplier: kwame, product: Product.cashew, recordedAt: date.add(const Duration(hours: 9)), bagWeights: [80, 80], recordedByUserId: 'secretary'));
    await deliveryRepository.save(Delivery(id: 'three', supplier: ibrahim, product: Product.cocoa, recordedAt: date.add(const Duration(hours: 10)), bagWeights: [50], recordedByUserId: 'secretary'));
    await deliveryRepository.save(Delivery(id: 'other-day', supplier: ibrahim, product: Product.sheaNuts, recordedAt: date.subtract(const Duration(days: 1)), bagWeights: [100], recordedByUserId: 'secretary'));

    final report = await reportRepository.forDate(date);

    expect(report.supplierCount, 2);
    expect(report.deliveryCount, 3);
    expect(report.totalBags, 6);
    expect(report.totalWeight, closeTo(453.5, 0.0001));
    expect(report.productTotals.map((total) => total.productName), ['Cashew', 'Cocoa']);
    expect(report.productTotals.first.bagCount, 5);
    expect(report.productTotals.first.totalWeight, closeTo(403.5, 0.0001));
    expect(report.productTotals.last.bagCount, 1);
    expect(report.productTotals.last.totalWeight, 50);
    expect(report.deliveries.first.supplier.type, SupplierType.aggregator);
  });
}
