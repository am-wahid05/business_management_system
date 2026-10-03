import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final supplier = Supplier(
    id: 'ALB-000184',
    name: 'Ibrahim Mensah',
    type: SupplierType.aggregator,
    town: 'Techiman',
    district: 'Techiman Municipal',
    region: 'Bono East',
  );

  test('calculates bag count and total weight from individual weights', () {
    final delivery = Delivery(
      id: 'delivery-1',
      supplier: supplier,
      product: Product.cashew,
      recordedAt: DateTime(2026, 9, 20, 10, 30),
      bagWeights: [82.5, 79.8, 81.2],
      recordedByUserId: 'secretary-1',
    );

    expect(delivery.numberOfBags, 3);
    expect(delivery.totalWeight, closeTo(243.5, 0.0001));
    expect(delivery.synchronizationStatus, SynchronizationStatus.pending);
  });

  test('does not expose a mutable bag-weight list', () {
    final weights = [50.0, 60.0];
    final delivery = Delivery(
      id: 'delivery-2',
      supplier: supplier,
      product: Product.cocoa,
      recordedAt: DateTime(2026, 9, 20),
      bagWeights: weights,
      recordedByUserId: 'secretary-1',
    );

    weights.add(70.0);

    expect(delivery.numberOfBags, 2);
    expect(delivery.totalWeight, closeTo(110.0, 0.0001));
  });

  test('rejects a delivery without any bag weights', () {
    expect(
      () => Delivery(
        id: 'delivery-3',
        supplier: supplier,
        product: Product.sheaNuts,
        recordedAt: DateTime(2026, 9, 20),
        bagWeights: [],
        recordedByUserId: 'secretary-1',
      ),
      throwsArgumentError,
    );
  });

  test('rejects non-positive or non-finite bag weights', () {
    for (final invalidWeight in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => Delivery(
          id: 'delivery-invalid',
          supplier: supplier,
          product: Product.cashew,
          recordedAt: DateTime(2026, 9, 20),
          bagWeights: [invalidWeight],
          recordedByUserId: 'secretary-1',
        ),
        throwsArgumentError,
      );
    }
  });
}
