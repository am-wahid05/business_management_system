import 'package:flutter_application_2/features/secretary/new_receiving_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the 30 weight boxes the weighing screen shows, with [entered] bags
/// filled in and the remaining boxes left empty.
List<String> weightBoxes(List<double> entered) {
  final boxes = List<String>.filled(30, '');
  for (var i = 0; i < entered.length; i++) {
    boxes[i] = entered[i].toString();
  }
  return boxes;
}

void main() {
  group('secretary bag weight entry', () {
    test('a single valid bag saves', () {
      final weights = parseEnteredBagWeights(weightBoxes([48.5]));
      expect(weights, [48.5]);
    });

    test('two valid bags save', () {
      final weights = parseEnteredBagWeights(weightBoxes([48.5, 51.2]));
      expect(weights, [48.5, 51.2]);
    });

    test('five valid bags save', () {
      final weights = parseEnteredBagWeights(
        weightBoxes([48.5, 51.2, 49.8, 50.1, 52.0]),
      );
      expect(weights, hasLength(5));
      expect(weights, [48.5, 51.2, 49.8, 50.1, 52.0]);
    });

    test('ten valid bags save', () {
      final weights = parseEnteredBagWeights(
        weightBoxes(List.generate(10, (i) => 40.0 + i)),
      );
      expect(weights, hasLength(10));
    });

    test('twenty-nine valid bags save', () {
      final weights = parseEnteredBagWeights(
        weightBoxes(List.generate(29, (i) => 40.0 + i)),
      );
      expect(weights, hasLength(29));
    });

    test('all thirty valid bags save', () {
      final weights = parseEnteredBagWeights(
        weightBoxes(List.generate(30, (i) => 40.0 + i)),
      );
      expect(weights, hasLength(30));
    });

    test('unused empty weight boxes are accepted, not treated as zero bags', () {
      // 5 entered bags, boxes 6-30 empty.
      final weights = parseEnteredBagWeights(
        weightBoxes([48.5, 51.2, 49.8, 50.1, 52.0]),
      );
      expect(weights, hasLength(5));
      expect(weights.any((weight) => weight == 0), isFalse);
      expect(weights.every((weight) => weight > 0), isTrue);
    });

    test('a gap after the entered bags is still accepted', () {
      final boxes = List<String>.filled(30, '');
      boxes[0] = '48.5';
      boxes[1] = '51.2';
      boxes[7] = '60.0';
      final weights = parseEnteredBagWeights(boxes);
      expect(weights, [48.5, 51.2, 60.0]);
    });

    test('a zero weight is rejected', () {
      expect(
        () => parseEnteredBagWeights(weightBoxes([48.5, 0, 52.0])),
        throwsA(isA<BagWeightValidationException>()),
      );
    });

    test('a negative weight is rejected', () {
      expect(
        () => parseEnteredBagWeights(weightBoxes([48.5, -2])),
        throwsA(isA<BagWeightValidationException>()),
      );
    });

    test('a non-numeric weight is rejected', () {
      final boxes = List<String>.filled(30, '');
      boxes[0] = '48.5';
      boxes[1] = 'abc';
      expect(
        () => parseEnteredBagWeights(boxes),
        throwsA(isA<BagWeightValidationException>()),
      );
    });

    test('no entered weights is rejected', () {
      expect(
        () => parseEnteredBagWeights(weightBoxes(const [])),
        throwsA(
          isA<BagWeightValidationException>().having(
            (e) => e.message,
            'message',
            contains('at least one bag weight'),
          ),
        ),
      );
    });

    test('all boxes empty is rejected', () {
      expect(
        () => parseEnteredBagWeights(List.filled(30, '')),
        throwsA(isA<BagWeightValidationException>()),
      );
    });

    test('whitespace-only boxes count as empty', () {
      final boxes = List.filled(30, '   ');
      boxes[0] = '48.5';
      final weights = parseEnteredBagWeights(boxes);
      expect(weights, [48.5]);
    });

    test('total weight only includes entered weights', () {
      final weights = parseEnteredBagWeights(
        weightBoxes([48.5, 51.2, 49.8, 50.1, 52.0]),
      );
      final total = weights.fold<double>(0, (sum, w) => sum + w);
      expect(total, closeTo(251.6, 0.0001));
    });

    test('saved bag count equals the number of entered weights', () {
      for (final count in [1, 2, 5, 10, 29, 30]) {
        final weights = parseEnteredBagWeights(
          weightBoxes(List.generate(count, (i) => 50.0)),
        );
        expect(weights, hasLength(count));
      }
    });

    test('the number of bags is never zero', () {
      expect(
        () => parseEnteredBagWeights(weightBoxes(const [])),
        throwsA(isA<BagWeightValidationException>()),
      );
    });
  });
}
