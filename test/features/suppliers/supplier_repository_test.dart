import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/suppliers/supplier_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime(2026, 9, 21, 8);
  late SupplierRepository repository;

  setUp(() {
    repository = SupplierRepository(now: () => fixedNow);
  });

  test('creates searchable suppliers with unique IDs', () async {
    final supplier = await repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.aggregator,
      phone: '0240000000',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    expect(supplier.id, 'ALB-000001');
    expect(supplier.createdAt, fixedNow);
    expect(repository.search('ibrahim').single.id, supplier.id);
    expect(repository.search('techiman').single.id, supplier.id);
  });

  group('search matches the ways an Admin looks a supplier up', () {
    /// Three suppliers with deliberately distinct name, id and contact so a
    /// search for one field cannot accidentally match another.
    Future<void> seedThree() async {
      await repository.create(
        name: 'Kofi Mensah',
        type: SupplierType.aggregator,
        phone: '0241111111',
        town: 'Techiman',
        district: 'Techiman Municipal',
        region: 'Bono East',
        notes: '',
      );
      await repository.create(
        name: 'Ama Owusu',
        type: SupplierType.farmer,
        phone: '0552222222',
        town: 'Kumasi',
        district: 'Kumasi Metropolitan',
        region: 'Ashanti',
        notes: '',
      );
      await repository.create(
        name: 'Yaw Boateng',
        type: SupplierType.farmer,
        phone: '0203333333',
        town: 'Tamale',
        district: 'Tamale Metropolitan',
        region: 'Northern',
        notes: '',
      );
    }

    test('finds a supplier by name', () async {
      await seedThree();

      final hits = repository.search('kofi');

      expect(hits.single.name, 'Kofi Mensah');
    });

    test('finds a supplier by supplier ID', () async {
      await seedThree();

      // The prefix alone narrows the list; a full id returns exactly one.
      final all = repository.suppliers.firstWhere(
        (supplier) => supplier.name == 'Kofi Mensah',
      );

      expect(repository.search(all.id), hasLength(1));
      // The ids share a prefix, so the prefix must not collapse to one match.
      expect(repository.search('ALB-'), hasLength(3));
    });

    test('finds a supplier by contact number', () async {
      await seedThree();

      // The stored contact is used rather than the value passed in, because
      // contacts are normalised on save. Searching a prefix of what is actually
      // held is what the Admin does when they type the start of a number.
      //
      // The supplier is located by exact name rather than through search(),
      // because a short term like "ama" legitimately matches several suppliers
      // once town and id are searched too.
      final stored = repository.suppliers
          .firstWhere((supplier) => supplier.name == 'Ama Owusu')
          .phone!;
      expect(repository.search(stored), hasLength(1));
      // A shared prefix can legitimately match more than one supplier, so the
      // assertion is that the right one is found rather than that it is alone.
      expect(
        repository.search(stored.substring(0, 3)).map((s) => s.name),
        contains('Ama Owusu'),
      );
    });

    test('finds a supplier from part of a contact number', () async {
      await seedThree();

      // Typing only the last digits of a number still narrows to its owner,
      // because a suffix like this is unique to that supplier.
      final stored = repository.suppliers
          .firstWhere((supplier) => supplier.name == 'Yaw Boateng')
          .phone!;
      final tail = stored.substring(stored.length - 4);
      expect(repository.search(tail).map((s) => s.name), ['Yaw Boateng']);
    });

    test('returns every supplier for an empty search', () async {
      await seedThree();

      expect(repository.search(''), hasLength(3));
      expect(repository.search('   '), hasLength(3));
    });

    test('returns nothing when nothing matches', () async {
      await seedThree();

      expect(repository.search('no such supplier'), isEmpty);
    });
  });

  test('rejects duplicate names case-insensitively', () async {
    await repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.farmer,
      phone: '0241234567',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    await expectLater(
      repository.create(
        name: '  ibrahim mensah ',
        type: SupplierType.aggregator,
        phone: '0241234567',
        town: 'Kumasi',
        district: 'Kumasi Metropolitan',
        region: 'Ashanti',
        notes: '',
      ),
      throwsStateError,
    );
  });

  test('filters history and calculates totals', () async {
    final supplier = await repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.aggregator,
      phone: '0241234567',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    repository.addDelivery(
      _delivery(supplier, Product.cashew, DateTime(2026, 9, 20), [82.5, 79.8]),
    );
    repository.addDelivery(
      _delivery(supplier, Product.cocoa, DateTime(2026, 9, 21), [50]),
    );
    repository.addDelivery(
      _delivery(supplier, Product.cashew, DateTime(2025, 9, 20), [100]),
    );

    final totals = repository.totals(
      supplier.id,
      product: Product.cashew,
      year: 2026,
    );
    expect(totals.deliveryCount, 1);
    expect(totals.bagCount, 2);
    expect(totals.totalWeight, closeTo(162.3, 0.0001));
    expect(
      repository
          .deliveryHistory(supplier.id, date: DateTime(2026, 9, 21))
          .single
          .product
          .id,
      Product.cocoa.id,
    );
  });

  test('deactivates instead of deleting a supplier', () async {
    final supplier = await repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.farmer,
      phone: '0241234567',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    final inactive = await repository.setActive(supplier.id, false);

    expect(inactive.isActive, isFalse);
    expect(repository.findById(supplier.id), same(inactive));
  });
}

Delivery _delivery(
  Supplier supplier,
  Product product,
  DateTime recordedAt,
  List<double> weights,
) {
  return Delivery(
    id: '${supplier.id}-${recordedAt.toIso8601String()}-${product.id}',
    supplier: supplier,
    product: product,
    recordedAt: recordedAt,
    bagWeights: weights,
    recordedByUserId: 'secretary-1',
  );
}
