import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/bulk_receiving_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3: the bulk / weighing-bridge record type and the individual
/// workflow that must not change.
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

  // A sentinel so an explicit `null` really means "no value supplied". Without
  // it, `total ?? 62430` would silently replace null with the default and the
  // "missing value" cases would never actually be exercised.
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

  group('record type', () {
    test('a plain delivery is individual by default', () {
      expect(individual([48.5]).recordType, DeliveryRecordType.individual);
      expect(individual([48.5]).isIndividual, isTrue);
      expect(individual([48.5]).isBulk, isFalse);
    });

    test('a bulk delivery reports its own type', () {
      expect(bulk().recordType, DeliveryRecordType.bulk);
      expect(bulk().isBulk, isTrue);
    });

    test('an unknown or missing stored value reads as individual', () {
      expect(DeliveryRecordType.parse(null), DeliveryRecordType.individual);
      expect(
        DeliveryRecordType.parse('nonsense'),
        DeliveryRecordType.individual,
      );
      expect(DeliveryRecordType.parse('bulk'), DeliveryRecordType.bulk);
    });
  });

  group('individual behaviour is unchanged', () {
    test('total is still the sum of the bag weights', () {
      expect(individual([48.5, 51.2, 49.8]).totalWeight, 149.5);
    });

    test('bag count is still the number of bag weights', () {
      expect(individual([48.5, 51.2, 49.8]).numberOfBags, 3);
    });

    test('a bulk total never leaks into an individual total', () {
      final delivery = individual([48.5, 51.2]);
      expect(delivery.bulkTotalWeight, isNull);
      expect(delivery.bulkBagCount, isNull);
      expect(delivery.totalWeight, 99.7);
    });

    test('an empty individual delivery is still rejected', () {
      expect(() => individual(const []), throwsArgumentError);
    });

    test('a non-positive individual weight is still rejected', () {
      expect(() => individual([0]), throwsArgumentError);
      expect(() => individual([-1]), throwsArgumentError);
    });
  });

  group('bulk totals use the stored values', () {
    test('total comes from the stored weighing-bridge total', () {
      expect(bulk(total: 62430).totalWeight, 62430);
    });

    test('bag count comes from the stored count', () {
      expect(bulk(bags: 1250).numberOfBags, 1250);
    });

    test('a bulk record has no bag weights at all', () {
      expect(bulk(bags: 1250).bagWeights, isEmpty);
    });

    test('bag weights are never manufactured from the total', () {
      final delivery = bulk(total: 62430, bags: 1250);
      // 1,250 bags must not become 1,250 rows of 49.944kg.
      expect(delivery.bagWeights, isEmpty);
      expect(delivery.numberOfBags, 1250);
      expect(delivery.totalWeight, 62430);
    });

    test('a bulk record with bag weights is rejected', () {
      expect(() => bulk(weights: const [62430]), throwsArgumentError);
      expect(
        () => bulk(weights: List.filled(1250, 49.944)),
        throwsArgumentError,
      );
    });
  });

  group('bulk validation', () {
    test('zero bags cannot be saved', () {
      expect(() => bulk(bags: 0), throwsArgumentError);
      expect(() => bulk(bags: -5), throwsArgumentError);
    });

    test('a missing bag count cannot be saved', () {
      expect(() => bulk(bags: null), throwsArgumentError);
    });

    test('a zero or negative weight cannot be saved', () {
      expect(() => bulk(total: 0), throwsArgumentError);
      expect(() => bulk(total: -10), throwsArgumentError);
    });

    test('a missing total cannot be saved', () {
      expect(() => bulk(total: null), throwsArgumentError);
    });
  });

  group('recorder attribution', () {
    test('a bulk record keeps the authenticated recorder', () {
      expect(bulk().recordedByUserId, 'user-secretary');
    });

    test('copyWith that does not mention bulk fields keeps them', () {
      final corrected = bulk().copyWith(status: DeliveryStatus.corrected);
      expect(corrected.bulkTotalWeight, 62430);
      expect(corrected.bulkBagCount, 1250);
      expect(corrected.isBulk, isTrue);
    });

    test('copyWith can change the bulk totals', () {
      final corrected = bulk().copyWith(
        bulkTotalWeight: 60000,
        bulkBagCount: 1200,
      );
      expect(corrected.totalWeight, 60000);
      expect(corrected.numberOfBags, 1200);
    });
  });

  group('weighing-bridge form validation', () {
    BulkReceivingInput parse(String bags, String total) =>
        parseBulkReceivingInput(bags: bags, totalWeight: total);

    test('accepts a valid entry', () {
      final input = parse('1250', '62430');
      expect(input.bagCount, 1250);
      expect(input.totalWeight, 62430);
    });

    test('accepts a thousands-separated total', () {
      expect(parse('1250', '62,430').totalWeight, 62430);
    });

    test('rejects zero and negative bags', () {
      expect(
        () => parse('0', '100'),
        throwsA(isA<BulkReceivingValidationException>()),
      );
      expect(
        () => parse('-3', '100'),
        throwsA(isA<BulkReceivingValidationException>()),
      );
    });

    test('rejects a non-integer bag count', () {
      expect(
        () => parse('12.5', '100'),
        throwsA(isA<BulkReceivingValidationException>()),
      );
    });

    test('rejects a zero, negative or missing total', () {
      for (final total in ['0', '-5', '']) {
        expect(
          () => parse('10', total),
          throwsA(isA<BulkReceivingValidationException>()),
          reason: 'total "$total" must be rejected',
        );
      }
    });

    test('keeps an optional note and drops a blank one', () {
      expect(
        parseBulkReceivingInput(
          bags: '5',
          totalWeight: '10',
          notes: ' Tarp ',
        ).notes,
        'Tarp',
      );
      expect(
        parseBulkReceivingInput(
          bags: '5',
          totalWeight: '10',
          notes: '   ',
        ).notes,
        isNull,
      );
    });
  });
}
