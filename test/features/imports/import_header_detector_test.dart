import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/features/imports/excel_import_service.dart';
import 'package:flutter_application_2/features/imports/import_header_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenize', () {
    test('ignores case, spacing and punctuation', () {
      expect(tokenize('Supplier  ID'), {'supplier', 'id'});
      expect(tokenize('supplier-id'), {'supplier', 'id'});
      expect(tokenize('Total Weight (kg)'), {'total', 'weight', 'kg'});
    });
  });

  group('detectFieldForHeader', () {
    test('recognises the common headers', () {
      expect(detectFieldForHeader('Date'), ImportField.date);
      expect(detectFieldForHeader('Supplier Name'), ImportField.supplierName);
      expect(detectFieldForHeader('Supplier ID'), ImportField.supplierId);
      expect(detectFieldForHeader('Total Weight'), ImportField.totalWeight);
      expect(detectFieldForHeader('Bag Weights'), ImportField.bagWeights);
      expect(detectFieldForHeader('District'), ImportField.district);
      expect(detectFieldForHeader('Region'), ImportField.region);
      expect(detectFieldForHeader('Recorded By'), ImportField.recordedBy);
    });

    test('does not match a field from a partial substring', () {
      // The old substring matching claimed 'Total Weight' for supplierName
      // because it contains the letters of 'name'.
      expect(
        detectFieldForHeader('Total Weight'),
        isNot(ImportField.supplierName),
      );
      // 'Bag 1 Recorded By' is not a date just because it contains no match.
      expect(detectFieldForHeader('Bag 3 Weight'), ImportField.totalWeight);
    });

    test('returns null for an unknown header', () {
      expect(detectFieldForHeader('Comment'), isNull);
      expect(detectFieldForHeader(''), isNull);
    });

    test('a bag count is not mistaken for a list of bag weights', () {
      // "Number of Bags" is a count, not a weight list, so it must not be
      // mapped to bagWeights, which would turn 1000 bags into 1000 kg.
      expect(
        detectFieldForHeader('Number of Bags'),
        isNot(ImportField.bagWeights),
      );
    });
  });

  group('guessMapping', () {
    test('maps each field to a different column', () {
      final mapping = guessMapping([
        'Date',
        'Supplier Name',
        'Product',
        'Total Weight',
        'Bag Weights',
      ]);
      expect(mapping.column(ImportField.date), 'Date');
      expect(mapping.column(ImportField.supplierName), 'Supplier Name');
      expect(mapping.column(ImportField.productName), 'Product');
      expect(mapping.column(ImportField.totalWeight), 'Total Weight');
      expect(mapping.column(ImportField.bagWeights), 'Bag Weights');
    });

    test('handles reordered columns', () {
      final mapping = guessMapping([
        'Total Weight',
        'Product',
        'Supplier Name',
        'Date',
      ]);
      expect(mapping.column(ImportField.totalWeight), 'Total Weight');
      expect(mapping.column(ImportField.productName), 'Product');
      expect(mapping.column(ImportField.supplierName), 'Supplier Name');
      expect(mapping.column(ImportField.date), 'Date');
    });

    test('never assigns one column to two fields', () {
      final mapping = guessMapping(['Date', 'Weight']);
      final used = mapping.columns.values.whereType<String>().toList();
      expect(used.toSet().length, used.length);
    });

    test('the product ID is left unmapped when there is no such column', () {
      final mapping = guessMapping(['Date', 'Supplier Name', 'Product']);
      expect(mapping.column(ImportField.productId), isNull);
    });
  });

  group('detectHeaderRow', () {
    test('finds the header below a title row', () {
      final List<List<String>> rows = [
        ['AL_BNC RECEIVING SUMMARY'],
        [''],
        ['Date', 'Supplier Name', 'Product', 'Total Weight'],
        ['26/09/2026', 'John Mensah', 'Cashew', '50,240'],
      ];
      expect(detectHeaderRow(rows), 2);
    });

    test('finds the header below several non-header rows', () {
      final List<List<String>> rows = [
        ['Company export'],
        ['Generated 26/09/2026'],
        ['Contact: 020 000 0000'],
        ['Date', 'Supplier Name', 'Total Weight'],
        ['26/09/2026', 'John Mensah', '50,240'],
      ];
      expect(detectHeaderRow(rows), 3);
    });

    test('returns row 0 when the header really is first', () {
      final rows = [
        ['Date', 'Supplier Name', 'Total Weight'],
        ['26/09/2026', 'John Mensah', '50,240'],
      ];
      expect(detectHeaderRow(rows), 0);
    });

    test('handles an empty sheet', () {
      expect(detectHeaderRow([]), 0);
    });
  });

  group('inferProductId', () {
    test('resolves a seeded product by name', () {
      expect(inferProductId('Cashew', Product.initialProducts), 'cashew');
      expect(inferProductId('Cocoa', Product.initialProducts), 'cocoa');
    });

    test('matches regardless of case and extra words', () {
      expect(inferProductId('Cashew Nuts', Product.initialProducts), 'cashew');
    });

    test('falls back to a stable slug for an unknown product', () {
      expect(inferProductId('Shea Nut', Product.initialProducts), 'shea_nut');
    });

    test('returns null for an empty name', () {
      expect(inferProductId('   ', Product.initialProducts), isNull);
    });
  });
}
