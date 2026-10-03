import 'package:flutter_application_2/features/credits/sms_credit_pricing.dart';
import 'package:flutter_application_2/features/credits/sms_credit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pricing is exact integer money', () {
    test('one credit is 5 pesewas, which is GH 0.05', () {
      expect(pesewasPerCredit, 5);
      expect(amountMinorForCredits(1), 5);
      expect(formatCediMinor(amountMinorForCredits(1)), 'GH₵0.05');
    });

    test('100 credits is GH 5.00', () {
      expect(amountMinorForCredits(100), 500);
      expect(formatTopUpTotal(100), 'GH₵5.00');
    });

    test('500 credits is GH 25.00', () {
      expect(amountMinorForCredits(500), 2500);
      expect(formatTopUpTotal(500), 'GH₵25.00');
    });

    test('1,000 credits is GH 50.00', () {
      expect(amountMinorForCredits(1000), 5000);
      expect(formatTopUpTotal(1000), 'GH₵50.00');
    });

    test('5,000 credits is GH 250.00', () {
      expect(amountMinorForCredits(5000), 25000);
      expect(formatTopUpTotal(5000), 'GH₵250.00');
    });

    test('the recommended 10,000 credits is GH 500.00', () {
      expect(recommendedTopUpCredits, 10000);
      expect(amountMinorForCredits(recommendedTopUpCredits), 50000);
      expect(formatTopUpTotal(recommendedTopUpCredits), 'GH₵500.00');
    });

    test('a large total never drifts by a floating point error', () {
      // 333,333 credits * 5 = 1,666,665 pesewas = GH 16,666.65 exactly.
      expect(amountMinorForCredits(333333), 1666665);
      expect(formatTopUpTotal(333333), 'GH₵16,666.65');
    });

    test('large amounts format with thousands separators', () {
      expect(formatCediMinor(50000), 'GH₵500.00');
      expect(formatCediMinor(5000000), 'GH₵50,000.00');
    });
  });

  group('top up quantity validation', () {
    test('a plain positive whole number is accepted', () {
      final result = validateCreditQuantity('500');
      expect(result.isValid, isTrue);
      expect(result.credits, 500);
      expect(result.message, isNull);
    });

    test('thousands separators are tolerated', () {
      expect(validateCreditQuantity('10,000').credits, 10000);
      expect(validateCreditQuantity('10 000').credits, 10000);
    });

    test('zero credits is rejected', () {
      final result = validateCreditQuantity('0');
      expect(result.isValid, isFalse);
      expect(result.error, CreditQuantityError.notPositive);
    });

    test('a negative value is rejected', () {
      expect(validateCreditQuantity('-5').isValid, isFalse);
    });

    test('a decimal value is rejected', () {
      final result = validateCreditQuantity('5.5');
      expect(result.isValid, isFalse);
      expect(result.error, CreditQuantityError.notAnInteger);
      expect(result.message, contains('whole number'));
    });

    test('malformed input is rejected', () {
      for (final value in ['abc', '5kg', 'e10', '--5', '5;drop']) {
        expect(
          validateCreditQuantity(value).isValid,
          isFalse,
          reason: '"$value" must be rejected',
        );
      }
    });

    test('empty input is rejected with a helpful message', () {
      final result = validateCreditQuantity('   ');
      expect(result.error, CreditQuantityError.empty);
      expect(result.message, contains('Enter the number'));
    });

    test('null input is rejected', () {
      expect(validateCreditQuantity(null).isValid, isFalse);
    });

    test('an unreasonably large purchase is rejected', () {
      final result = validateCreditQuantity('99999999');
      expect(result.isValid, isFalse);
      expect(result.error, CreditQuantityError.tooLarge);
    });

    test('the maximum allowed purchase is accepted', () {
      expect(validateCreditQuantity('$maxTopUpCredits').isValid, isTrue);
    });
  });

  group('balance visibility is company scoped', () {
    final snapshot = SmsCreditSnapshot(
      balances: const [
        SmsCreditBalance(
          companyId: 'company-a',
          companyName: 'AL-BNC Ventures',
          balance: 10000,
        ),
        SmsCreditBalance(
          companyId: 'company-b',
          companyName: 'ABC Traders',
          balance: 2500,
        ),
      ],
      transactions: const [],
    );

    test('a company sees its own balance', () {
      expect(snapshot.balanceFor('company-a')?.balance, 10000);
      expect(snapshot.balanceFor('company-b')?.balance, 2500);
    });

    test('a zero balance reports as exhausted', () {
      const balance = SmsCreditBalance(
        companyId: 'c',
        companyName: 'C',
        balance: 0,
      );
      expect(balance.isExhausted, isTrue);
    });

    test('an unknown company resolves to no balance', () {
      expect(snapshot.balanceFor('company-c'), isNull);
    });
  });

  group('ledger entries are parsed from the server ledger', () {
    test('a usage row has a negative credit and a balance after', () {
      final row = SmsCreditTransaction.fromRow({
        'id': 'r1',
        'company_id': 'company-a',
        'type': 'usage',
        'credits': -1,
        'balance_after': 99,
        'status': 'successful',
        'created_at': '2026-09-25T10:00:00Z',
        'amount_minor': null,
        'currency': null,
        'payment_reference': null,
      });
      expect(row.isUsage, isTrue);
      expect(row.credits, -1);
      expect(row.balanceAfter, 99);
      expect(row.amountMinor, isNull);
    });

    test('a purchase row keeps the integer amount and reference', () {
      final row = SmsCreditTransaction.fromRow({
        'id': 'r2',
        'company_id': 'company-a',
        'type': 'purchase',
        'credits': 10000,
        'balance_after': 10000,
        'status': 'successful',
        'created_at': '2026-09-25T10:00:00Z',
        'amount_minor': 50000,
        'currency': 'GHS',
        'payment_reference': 'BMS-SMS-abc123',
      });
      expect(row.isPurchase, isTrue);
      expect(row.amountMinor, 50000);
      expect(row.paymentReference, 'BMS-SMS-abc123');
      expect(formatCediMinor(row.amountMinor!), 'GH₵500.00');
    });

    test('a refund row is positive', () {
      final row = SmsCreditTransaction.fromRow({
        'id': 'r3',
        'company_id': 'company-a',
        'type': 'refund',
        'credits': 1,
        'balance_after': 100,
        'status': 'successful',
        'created_at': '2026-09-25T10:00:00Z',
        'amount_minor': null,
        'currency': null,
        'payment_reference': null,
      });
      expect(row.isRefund, isTrue);
      expect(row.credits, 1);
    });
  });

  group('no client path can create credits', () {
    test('offline mode reports no balance rather than inventing one', () async {
      const service = SmsCreditService(null);
      expect(service.isAvailable, isFalse);
      final snapshot = await service.load(companyId: 'company-a');
      expect(snapshot.balances, isEmpty);
      expect(snapshot.transactions, isEmpty);
    });

    test('top up never claims a payment succeeded', () async {
      const service = SmsCreditService(null);
      final outcome = await service.startTopUp(credits: 10000);
      expect(outcome.started, isFalse);
      expect(outcome.checkoutUrl, isNull);
      expect(outcome.message, contains('not available yet'));
      expect(outcome.message, contains('No credits have been added'));
    });

    test('top up rejects an invalid quantity', () async {
      const service = SmsCreditService(null);
      final outcome = await service.startTopUp(credits: 0);
      expect(outcome.started, isFalse);
      expect(outcome.message, contains('valid number of credits'));
    });
  });
}
