import 'package:flutter_application_2/features/products/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late ProductRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(':memory:', options: OpenDatabaseOptions(
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
      },
    ));
    repository = ProductRepository(database);
  });

  tearDown(() => database.close());

  test('seeds the three initial products once', () async {
    await repository.seedInitialProducts();
    await repository.seedInitialProducts();

    final products = await repository.all();
    expect(products.map((product) => product.name), containsAll(['Cashew', 'Cocoa', 'Shea Nuts']));
    expect(products.length, 3);
  });

  test('creates future products and rejects duplicate names', () async {
    final product = await repository.create('Maize');

    expect(product.name, 'Maize');
    expect(product.isActive, isTrue);
    expect((await repository.all()).single.name, 'Maize');
    expect(() => repository.create(' maize '), throwsStateError);
  });

  test('updates product name and active status without deleting it', () async {
    await repository.seedInitialProducts();
    final cashew = (await repository.all()).firstWhere((product) => product.id == 'cashew');

    final inactive = await repository.setActive(cashew, false);
    expect(inactive.isActive, isFalse);
    expect((await repository.all(activeOnly: true)).any((product) => product.id == 'cashew'), isFalse);
    expect((await repository.all()).any((product) => product.id == 'cashew'), isTrue);

    final renamed = await repository.update(inactive.copyWith(name: 'Raw Cashew'));
    expect(renamed.name, 'Raw Cashew');
    expect(renamed.updatedAt.isAfter(renamed.createdAt), isTrue);
  });
}
