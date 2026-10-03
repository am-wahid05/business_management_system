import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/features/products/product_database.dart';
import 'package:flutter_application_2/features/products/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The product dropdown must always present Cashew, then Shea Nuts, then Cocoa,
/// with anything an admin adds afterwards, and must never leak between
/// companies.
void main() {
  late Database database;

  setUp(() async {
    sqfliteFfiInit();
    // The real production schema, so the products table matches the app.
    database = await ProductDatabase.open(databasePath: inMemoryDatabasePath);
  });

  tearDown(() => database.close());

  ProductRepository repositoryFor(String? companyId) =>
      ProductRepository(database, companyIdProvider: () => companyId);

  List<String> namesOf(List<Product> products) =>
      products.map((product) => product.name).toList();

  group('the required display order', () {
    test('starts as Cashew, Shea Nuts, Cocoa', () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      final products = await repository.all();

      expect(
        namesOf(products),
        ['Cashew', 'Shea Nuts', 'Cocoa'],
      );
    });

    test('the product ids are the existing ones and are not renamed', () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      final ids = (await repository.all()).map((p) => p.id).toList();

      // The three products keep their original ids.
      expect(ids, ['cashew', 'shea_nuts', 'cocoa']);
      expect(Product.initialProducts.map((p) => p.id), [
        'cashew',
        'shea_nuts',
        'cocoa',
      ]);
    });

    test('the order is not alphabetical', () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      final names = namesOf(await repository.all());
      final alphabetical = [...names]..sort();
      // Cashew, Cocoa, Shea Nuts would be alphabetical; that is NOT the order.
      expect(names, isNot(alphabetical));
      expect(names.indexOf('Shea Nuts'), lessThan(names.indexOf('Cocoa')));
    });

    test('seeding twice does not duplicate the products', () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      await repository.seedInitialProducts();
      expect(await repository.all(), hasLength(3));
    });
  });

  group('admin added products', () {
    test('a new product appears after the three initial products', () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      await repository.create('Coffee');

      expect(
        namesOf(await repository.all()),
        ['Cashew', 'Shea Nuts', 'Cocoa', 'Coffee'],
      );
    });

    test('several added products are ordered alphabetically after them',
        () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      await repository.create('Coffee');
      await repository.create('Almond');
      await repository.create('Zinc');

      expect(
        namesOf(await repository.all()),
        ['Cashew', 'Shea Nuts', 'Cocoa', 'Almond', 'Coffee', 'Zinc'],
      );
    });

    test('adding a product does not disturb the three initial ones', () async {
      final repository = repositoryFor('company-a');
      await repository.seedInitialProducts();
      final before = await repository.all();
      await repository.create('Coffee');
      final after = await repository.all();

      // The first three are untouched.
      expect(after.take(3).map((p) => p.id), before.map((p) => p.id));
    });
  });

  group('company isolation', () {
    test('company A products do not appear for company B', () async {
      await repositoryFor('company-a').seedInitialProducts();
      await repositoryFor('company-a').create('Coffee');

      final forB = await repositoryFor('company-b').all();
      expect(forB, isEmpty);
    });

    test('each company seeds its own copy independently', () async {
      await repositoryFor('company-a').seedInitialProducts();
      await repositoryFor('company-b').seedInitialProducts();

      expect(namesOf(await repositoryFor('company-a').all()),
          ['Cashew', 'Shea Nuts', 'Cocoa']);
      expect(namesOf(await repositoryFor('company-b').all()),
          ['Cashew', 'Shea Nuts', 'Cocoa']);

      // A product added by one company is invisible to the other.
      await repositoryFor('company-a').create('Coffee');
      expect(await repositoryFor('company-b').all(), hasLength(3));
    });
  });
}
