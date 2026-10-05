import 'package:flutter_application_2/features/receiving/sms_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 section 28D/28E: the existing supplier contact is the pre-filled
/// starting point, and duplicate numbers are detected using the project's
/// existing phone normalization rather than raw string comparison.
void main() {
  group('phone normalization is reused, not reinvented', () {
    test('equivalent formats normalize to the same number', () {
      const local = '0241234567';
      const international = '+233241234567';
      const withoutPlus = '233241234567';
      expect(GhanaPhoneNumber.normalize(local), '233241234567');
      expect(GhanaPhoneNumber.normalize(international), '233241234567');
      expect(GhanaPhoneNumber.normalize(withoutPlus), '233241234567');
      expect(
        GhanaPhoneNumber.normalize(local),
        GhanaPhoneNumber.normalize(international),
      );
    });

    test('invalid numbers are rejected', () {
      expect(GhanaPhoneNumber.normalize(null), isNull);
      expect(GhanaPhoneNumber.normalize(''), isNull);
      expect(GhanaPhoneNumber.normalize('12345'), isNull);
    });
  });

  group('pre-filled recipient list (28D)', () {
    test('an existing supplier contact is pre-filled', () {
      final list = initialSmsRecipients('0241234567');
      expect(list.uniqueCount, 1);
      expect(list.unique.single.normalized, '233241234567');
      expect(list.rejected, isEmpty);
    });

    test('the pre-filled value keeps what the secretary typed for display', () {
      final list = initialSmsRecipients('0241234567');
      expect(list.unique.single.raw, '0241234567');
    });

    test('a missing contact gives an empty list rather than an error', () {
      expect(initialSmsRecipients(null).isEmpty, isTrue);
      expect(initialSmsRecipients('   ').isEmpty, isTrue);
    });

    test('an invalid saved contact is reported, not guessed at', () {
      final list = initialSmsRecipients('12345');
      expect(list.isEmpty, isTrue);
      expect(list.rejected, ['12345']);
    });
  });

  group('duplicate detection (28E)', () {
    test('the same number entered twice counts once', () {
      final list = SmsRecipientList.build([
        '0241234567',
        '0559876543',
        '0241234567',
      ]);
      expect(list.uniqueCount, 2);
      expect(list.hasDuplicates, isTrue);
      expect(list.duplicates, ['233241234567']);
    });

    test('a duplicate consumes no extra credit', () {
      // One credit per UNIQUE recipient, so a repeated number must not add one.
      final withDuplicate = SmsRecipientList.build([
        '0241234567',
        '0559876543',
        '0241234567',
      ]);
      final allUnique = SmsRecipientList.build(['0241234567', '0559876543']);
      expect(withDuplicate.uniqueCount, allUnique.uniqueCount);
      expect(withDuplicate.uniqueCount, 2);
    });

    test('two equivalent formats are recognised as one recipient', () {
      final list = SmsRecipientList.build(['0241234567', '+233241234567']);
      expect(list.uniqueCount, 1);
      expect(list.duplicates, ['233241234567']);
    });

    test('a number already saved as the supplier contact is a duplicate', () {
      final start = initialSmsRecipients('0241234567');
      expect(start.contains('+233241234567'), isTrue);
      expect(start.contains('0559876543'), isFalse);

      final combined = SmsRecipientList.build([
        ...start.unique.map((recipient) => recipient.raw),
        '+233241234567',
      ]);
      expect(combined.uniqueCount, 1);
    });

    test('invalid entries are reported instead of being dropped silently', () {
      final list = SmsRecipientList.build(['0241234567', 'abc', '999']);
      expect(list.uniqueCount, 1);
      expect(list.rejected, ['abc', '999']);
    });

    test('blank entries are ignored', () {
      final list = SmsRecipientList.build(['', '   ', '0241234567']);
      expect(list.uniqueCount, 1);
      expect(list.rejected, isEmpty);
    });

    test('order is preserved so the UI can show the reviewed list', () {
      final list = SmsRecipientList.build([
        '0201112222',
        '0241234567',
        '0559876543',
      ]);
      expect(list.unique.map((recipient) => recipient.normalized).toList(), [
        '233201112222',
        '233241234567',
        '233559876543',
      ]);
    });
  });

  group('credit counting per unique recipient', () {
    test('1 unique recipient requires 1 credit', () {
      expect(SmsRecipientList.build(['0241234567']).uniqueCount, 1);
    });

    test('2 unique recipients require 2 credits', () {
      expect(
        SmsRecipientList.build(['0241234567', '0559876543']).uniqueCount,
        2,
      );
    });

    test('3 unique recipients require 3 credits', () {
      expect(
        SmsRecipientList.build(['0241234567', '0559876543', '0201112222'])
            .uniqueCount,
        3,
      );
    });

    test('duplicates do not consume duplicate credits', () {
      final list = SmsRecipientList.build([
        '0241234567',
        '0559876543',
        '0241234567',
      ]);
      // The example from the specification: 2 unique recipients = 2 credits.
      expect(list.uniqueCount, 2);
    });
  });
}
