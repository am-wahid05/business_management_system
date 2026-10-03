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

  test('creates searchable suppliers with unique IDs', () {
    final supplier = repository.create(
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

  test('rejects duplicate names case-insensitively', () {
    repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.farmer,
      phone: '',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    expect(
      () => repository.create(
        name: '  ibrahim mensah ',
        type: SupplierType.aggregator,
        phone: '',
        town: 'Kumasi',
        district: 'Kumasi Metropolitan',
        region: 'Ashanti',
        notes: '',
      ),
      throwsStateError,
    );
  });

  test('filters history and calculates totals', () {
    final supplier = repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.aggregator,
      phone: '',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    repository.addDelivery(_delivery(supplier, Product.cashew, DateTime(2026, 9, 20), [82.5, 79.8]));
    repository.addDelivery(_delivery(supplier, Product.cocoa, DateTime(2026, 9, 21), [50]));
    repository.addDelivery(_delivery(supplier, Product.cashew, DateTime(2025, 9, 20), [100]));

    final totals = repository.totals(supplier.id, product: Product.cashew, year: 2026);
    expect(totals.deliveryCount, 1);
    expect(totals.bagCount, 2);
    expect(totals.totalWeight, closeTo(162.3, 0.0001));
    expect(
      repository.deliveryHistory(supplier.id, date: DateTime(2026, 9, 21)).single.product.id,
      Product.cocoa.id,
    );
  });

  test('deactivates instead of deleting a supplier', () {
    final supplier = repository.create(
      name: 'Ibrahim Mensah',
      type: SupplierType.farmer,
      phone: '',
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
      notes: '',
    );

    final inactive = repository.setActive(supplier.id, false);

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
