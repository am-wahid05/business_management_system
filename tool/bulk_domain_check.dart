// Temporary verification harness for the Phase 3 domain rules.
// Run with: dart run tool/bulk_domain_check.dart
import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';

int _failures = 0;

void check(String name, bool condition) {
  if (condition) {
    print('PASS  $name');
  } else {
    _failures++;
    print('FAIL  $name');
  }
}

void checkThrows(String name, void Function() body) {
  try {
    body();
    _failures++;
    print('FAIL  $name (did not throw)');
  } on ArgumentError {
    print('PASS  $name');
  }
}

void main() {
  final supplier = Supplier(
    internalId: 's1',
    id: 'S-1',
    name: 'John Mensah',
    type: SupplierType.farmer,
    town: 'Kumasi',
    district: 'Ashanti',
    region: 'Ashanti',
  );
  final product = Product(id: 'p1', name: 'Cocoa');

  Delivery individual(List<double> weights) => Delivery(
    id: 'd1',
    supplier: supplier,
    product: product,
    recordedAt: DateTime(2026, 9, 26),
    bagWeights: weights,
    recordedByUserId: 'user-secretary',
  );

  // A sentinel so an explicit `null` really means "no value supplied".
  const Object missing = Object();

  Delivery bulk({
    Object? total = 62430,
    Object? bags = 1250,
    List<double> weights = const [],
  }) => Delivery(
    id: 'd2',
    supplier: supplier,
    product: product,
    recordedAt: DateTime(2026, 9, 26),
    bagWeights: weights,
    recordedByUserId: 'user-secretary',
    recordType: DeliveryRecordType.bulk,
    bulkTotalWeight: total == missing ? null : (total as num?)?.toDouble(),
    bulkBagCount: bags == missing ? null : (bags as num?)?.toInt(),
  );

  // --- record type ---
  check(
    'a plain delivery is individual by default',
    individual([48.5]).recordType == DeliveryRecordType.individual &&
        !individual([48.5]).isBulk,
  );
  check('a bulk delivery reports its own type', bulk().isBulk);
  check(
    'missing or unknown stored value reads as individual',
    DeliveryRecordType.parse(null) == DeliveryRecordType.individual &&
        DeliveryRecordType.parse('nonsense') == DeliveryRecordType.individual &&
        DeliveryRecordType.parse('bulk') == DeliveryRecordType.bulk,
  );

  // --- individual unchanged ---
  check(
    'individual total is still the sum of bag weights',
    individual([48.5, 51.2, 49.8]).totalWeight == 149.5,
  );
  check(
    'individual bag count is still bagWeights.length',
    individual([48.5, 51.2, 49.8]).numberOfBags == 3,
  );
  check(
    'individual record carries no bulk fields',
    individual([48.5, 51.2]).bulkTotalWeight == null &&
        individual([48.5, 51.2]).bulkBagCount == null &&
        individual([48.5, 51.2]).totalWeight == 99.7,
  );
  checkThrows('empty individual still rejected', () => individual(const []));
  checkThrows('zero individual weight rejected', () => individual([0]));

  // --- bulk totals ---
  check('bulk total comes from the stored value', bulk(total: 62430).totalWeight == 62430);
  check('bulk bag count comes from the stored value', bulk(bags: 1250).numberOfBags == 1250);
  check('bulk has no bag weights', bulk(bags: 1250).bagWeights.isEmpty);
  check(
    'weights are never distributed across invented bags',
    bulk(total: 62430, bags: 1250).bagWeights.isEmpty &&
        bulk(total: 62430, bags: 1250).totalWeight == 62430 &&
        bulk(total: 62430, bags: 1250).numberOfBags == 1250,
  );
  checkThrows(
    'a bulk record carrying bag weights is rejected',
    () => bulk(weights: const [62430]),
  );
  checkThrows(
    '1250 fake bags are rejected',
    () => bulk(weights: List.filled(1250, 49.944)),
  );

  // --- bulk validation ---
  checkThrows('zero bags rejected', () => bulk(bags: 0));
  checkThrows('negative bags rejected', () => bulk(bags: -5));
  checkThrows('missing bag count rejected', () => bulk(bags: null));
  checkThrows('zero total rejected', () => bulk(total: 0));
  checkThrows('negative total rejected', () => bulk(total: -10));
  checkThrows('missing total rejected', () => bulk(total: null));

  // --- recorder attribution / copyWith safety ---
  check(
    'a bulk record keeps the authenticated recorder',
    bulk().recordedByUserId == 'user-secretary',
  );
  final corrected = bulk().copyWith(status: DeliveryStatus.corrected);
  check(
    'copyWith without bulk args keeps the bulk values',
    corrected.bulkTotalWeight == 62430 &&
        corrected.bulkBagCount == 1250 &&
        corrected.isBulk,
  );
  final edited = bulk().copyWith(bulkTotalWeight: 60000, bulkBagCount: 1200);
  check(
    'copyWith can change the bulk values',
    edited.totalWeight == 60000 && edited.numberOfBags == 1200,
  );
  final individualCopied = individual([48.5, 51.2])
      .copyWith(recordedByUserId: 'other-user');
  check(
    'copyWith on an individual delivery still derives the total',
    individualCopied.totalWeight == 99.7 && individualCopied.numberOfBags == 2,
  );

  print('');
  print(_failures == 0 ? 'ALL CHECKS PASSED' : '$_failures CHECK(S) FAILED');
}
