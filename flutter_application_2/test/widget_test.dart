import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_application_2/app/albnc_app.dart';
import 'package:flutter_application_2/features/products/product_repository.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/auth/local_auth_repository.dart';

void main() {
  late Database database;
  late ProductRepository productRepository;
  late DeliveryRepository deliveryRepository;
  late LocalAuthRepository authRepository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
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
          await database.execute('''
          CREATE TABLE users (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL COLLATE NOCASE UNIQUE,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            password_salt TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        },
      ),
    );
    productRepository = ProductRepository(database);
    deliveryRepository = DeliveryRepository(database);
    authRepository = LocalAuthRepository(database);
    await productRepository.seedInitialProducts();
  });

  tearDown(() => database.close());

  testWidgets('opens the branded login shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      AlbncApp(
        productRepository: productRepository,
        deliveryRepository: deliveryRepository,
        authRepository: authRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Company Management'), findsOneWidget);
    expect(find.text('Open Secretary App'), findsNothing);
    expect(find.text('Open Owner / Admin App'), findsNothing);
  });

  testWidgets('does not expose dashboard shortcuts before authentication', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      AlbncApp(
        productRepository: productRepository,
        deliveryRepository: deliveryRepository,
        authRepository: authRepository,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Open Secretary App'), findsNothing);
    expect(find.text('Owner / Admin Dashboard'), findsNothing);
  });
}
