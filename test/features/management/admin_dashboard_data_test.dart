import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/management/admin_dashboard_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates dashboard metrics from actual deliveries', () {
    final supplier = Supplier(
      id: 'ALB-000001',
      name: 'Ibrahim Mensah',
      type: SupplierType.aggregator,
      town: 'Techiman',
      district: 'Techiman Municipal',
      region: 'Bono East',
    );
    final data = AdminDashboardData([
      Delivery(
        id: 'one',
        supplier: supplier,
        product: Product.cashew,
        recordedAt: DateTime(2026, 9, 21),
        bagWeights: [82.5, 79.8],
        recordedByUserId: 'secretary',
      ),
      Delivery(
        id: 'two',
        supplier: supplier,
        product: Product.cocoa,
        recordedAt: DateTime(2026, 9, 21),
        bagWeights: [50],
        recordedByUserId: 'secretary',
      ),
    ]);

    expect(data.supplierCount, 1);
    expect(data.deliveryCount, 2);
    expect(data.bagCount, 3);
    expect(data.totalWeight, closeTo(212.3, 0.0001));
    expect(data.productTotals['cashew']!.bags, 2);
    expect(data.productTotals['cocoa']!.weight, 50);
    expect(data.synchronizationTotals['pending'], 2);
  });

  test('admin resolves every weight to the profile for the recorded user', () {
    final supplier = Supplier(
      id: 'supplier',
      name: 'Supplier',
      type: SupplierType.farmer,
      town: '',
      district: '',
      region: '',
    );
    final delivery = Delivery(
      id: 'delivery',
      supplier: supplier,
      product: Product.cashew,
      recordedAt: DateTime(2026, 9, 21),
      bagWeights: [80, 75],
      recordedByUserId: 'secretary-a',
      bagRecordedByUserIds: ['secretary-a', 'secretary-b'],
    );
    final data = AdminDashboardData(
      [delivery],
      recorderNames: const {
        'secretary-a': 'Secretary A',
        'secretary-b': 'Secretary B',
      },
    );

    expect(data.recorderName(delivery.recordedByUserId), 'Secretary A');
    expect(data.recorderName(delivery.recorderForBag(0)), 'Secretary A');
    expect(data.recorderName(delivery.recorderForBag(1)), 'Secretary B');
    expect(data.recorderName(null), 'Not recorded');
  });
}
