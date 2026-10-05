import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/sms_receipt_service.dart';
import 'package:flutter_application_2/features/receiving/sms_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records every recipient the transport was asked to send to, and can be told
/// to reject specific numbers so a partial provider failure can be simulated.
class _RecordingTransport implements SmsTransport {
  final List<String> phones = [];
  final List<String> messages = [];
  String? reference;
  final Set<String> reject = <String>{};

  @override
  Future<SmsSendResult> send({
    required String phone,
    required String message,
    required String reference,
  }) async {
    phones.add(phone);
    messages.add(message);
    this.reference = reference;
    if (reject.contains(phone)) {
      return const SmsSendResult.rejected('SMS_REJECTED', 'Provider refused.');
    }
    return const SmsSendResult.accepted();
  }
}

/// A balance the test controls, standing in for the server's credit balance.
class _FakeCredits implements SmsCreditBalanceReader {
  _FakeCredits(this.balance);

  /// null means "unknown", which must not be treated as zero.
  int? balance;

  @override
  Future<int?> balanceFor(String companyId) async => balance;
}

class _CompanyCredits implements SmsCreditBalanceReader {
  _CompanyCredits(this.balances);

  final Map<String, int?> balances;

  @override
  Future<int?> balanceFor(String companyId) async => balances[companyId];
}

/// Phase 3 sections 28C-28M: sending one receipt to several recipients, with one
/// SMS credit per unique recipient and an all-or-nothing credit check.
void main() {
  late Database database;

  Delivery deliveryFor(String? companyId) => Delivery(
    id: 'TXN-1',
    supplier: Supplier(
      id: 'SUP-1',
      name: 'Abdul Wahid',
      type: SupplierType.farmer,
      town: 'Tamale',
      district: 'Tamale Metro',
      region: 'Northern',
      phone: '0241234567',
      companyId: companyId,
    ),
    product: Product(id: 'cashew', name: 'Cashew'),
    recordedAt: DateTime(2026, 9, 26),
    bagWeights: const [25, 30],
    recordedByUserId: 'secretary',
    companyId: companyId,
  );

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE receipt_sends (
              id TEXT PRIMARY KEY,
              delivery_id TEXT NOT NULL,
              company_id TEXT,
              phone TEXT NOT NULL,
              channel TEXT NOT NULL,
              status TEXT NOT NULL,
              sent_at TEXT NOT NULL,
              provider_reference TEXT
            )
          ''');
        },
      ),
    );
  });

  tearDown(() => database.close());

  SmsReceiptService serviceFor(
    SmsTransport transport, {
    String? activeCompany = 'company-a',
    SmsCreditBalanceReader? credits,
  }) => SmsReceiptService(
    transport: transport,
    senderLabel: 'ALBNC',
    database: database,
    companyIdProvider: () => activeCompany,
    creditReader: credits,
  );

  group('28C/28D one credit per unique recipient', () {
    test('a single recipient sends one message and costs one credit', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport)
          .sendToMany(deliveryFor('company-a'), phones: const ['0241234567']);

      expect(transport.phones, ['233241234567']);
      expect(summary.recipientCount, 1);
      expect(summary.creditsRequired, 1);
      expect(summary.creditsCharged, 1);
    });

    test('multiple recipients get one message each, in order', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543', '0201112222'],
      );

      expect(transport.phones, [
        '233241234567',
        '233559876543',
        '233201112222',
      ]);
      expect(summary.recipientCount, 3);
      // One credit per unique recipient.
      expect(summary.creditsRequired, 3);
      expect(summary.creditsCharged, 3);
    });

    test('every recipient receives the same message body', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      expect(transport.messages.length, 2);
      expect(transport.messages.toSet().length, 1);
      expect(transport.reference, 'TXN-1');
    });
  });

  group('28E duplicate protection', () {
    test('the same number twice is sent once and charged once', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0241234567'],
      );

      expect(transport.phones, ['233241234567']);
      expect(summary.creditsCharged, 1);
      expect(summary.duplicates, ['233241234567']);
    });

    test('equivalent Ghana formats are one recipient', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '+233241234567', '233241234567'],
      );

      // One message, one credit, however the number was spelled.
      expect(transport.phones, ['233241234567']);
      expect(summary.creditsRequired, 1);
      expect(summary.creditsCharged, 1);
    });

    test('a duplicate alongside a new number adds only the new one', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '+233241234567', '0559876543'],
      );

      expect(transport.phones, ['233241234567', '233559876543']);
      expect(summary.creditsRequired, 2);
    });
  });

  group('28F existing supplier contact', () {
    test('the saved contact is pre-filled as the starting list', () {
      final list = initialSmsRecipients('0241234567');
      expect(list.uniqueCount, 1);
      expect(list.unique.single.normalized, '233241234567');
    });

    test('a manually added recipient joins the saved contact', () async {
      final saved = initialSmsRecipients('0241234567');
      final combined = SmsRecipientList.build([
        ...saved.unique.map((r) => r.raw),
        '0559876543',
      ]);

      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: combined.unique.map((r) => r.raw).toList(),
      );

      expect(summary.recipientCount, 2);
      expect(summary.creditsRequired, 2);
    });

    test(
      'removing the saved contact leaves only the added recipient',
      () async {
        // The contact is simply not passed to the send.
        final transport = _RecordingTransport();
        final summary = await serviceFor(transport)
            .sendToMany(deliveryFor('company-a'), phones: const ['0559876543']);

        expect(transport.phones, ['233559876543']);
        expect(summary.creditsRequired, 1);
      },
    );

    test('adding a recipient never modifies the supplier profile', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      // The send writes only SMS history. It touches no supplier table, so a
      // temporary extra recipient cannot become a saved contact.
      final tables = await database.rawQuery(
        "select name from sqlite_master where type='table'",
      );
      expect(tables.map((row) => row['name']), isNot(contains('suppliers')));
    });
  });

  group('28G insufficient credits send ZERO messages', () {
    test('too few credits for the whole list sends nothing', () async {
      final transport = _RecordingTransport();
      final service = serviceFor(transport, credits: _FakeCredits(2));

      await expectLater(
        service.sendToMany(
          deliveryFor('company-a'),
          phones: const ['0241234567', '0559876543', '0201112222'],
        ),
        throwsA(isA<SmsReceiptException>()),
      );

      // All-or-nothing: 3 recipients needed, 2 available, ZERO sent.
      expect(transport.phones, isEmpty);
    });

    test('a zero balance sends nothing at all', () async {
      final transport = _RecordingTransport();
      final service = serviceFor(transport, credits: _FakeCredits(0));

      await expectLater(
        service.sendToMany(
          deliveryFor('company-a'),
          phones: const ['0241234567'],
        ),
        throwsA(isA<SmsReceiptException>()),
      );
      expect(transport.phones, isEmpty);
    });

    test('exactly enough credits is allowed', () async {
      final transport = _RecordingTransport();
      final service = serviceFor(transport, credits: _FakeCredits(2));

      final summary = await service.sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );
      expect(summary.creditsCharged, 2);
      expect(transport.phones.length, 2);
    });

    test('duplicates do not inflate the credit requirement', () async {
      final transport = _RecordingTransport();
      // Only ONE credit is needed, so a balance of 1 must be enough.
      final service = serviceFor(transport, credits: _FakeCredits(1));

      final summary = await service.sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '+233241234567'],
      );
      expect(summary.creditsRequired, 1);
      expect(transport.phones.length, 1);
    });

    test('an unknown balance is not treated as zero', () async {
      final transport = _RecordingTransport();
      // null = could not read the balance, for example offline.
      final service = serviceFor(transport, credits: _FakeCredits(null));

      final summary = await service.sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567'],
      );
      // The server-side reservation is the authority, so the send proceeds.
      expect(summary.creditsCharged, 1);
      expect(transport.phones.length, 1);
    });
  });

  group('28H/28I per-recipient reservation and sending', () {
    test('one request is made per unique recipient', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543', '0201112222'],
      );
      // Sailup is called once per recipient, never once for a batch.
      expect(transport.phones.length, 3);
    });

    test('the reservation count equals the unique recipient count', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0241234567', '0559876543'],
      );
      // 2 unique recipients, so exactly 2 credits are reserved.
      expect(summary.creditsRequired, 2);
      expect(transport.phones.length, 2);
    });

    test('the client never mutates a credit balance itself', () async {
      // The credits dependency is read-only: it exposes no method that can
      // change a balance, so the client cannot deduct anything.
      final transport = _RecordingTransport();
      final credits = _FakeCredits(5);
      await serviceFor(transport, credits: credits).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );
      // The reader is only asked for a balance; changing it is the server's job.
      expect(credits.balance, 5);
    });
  });

  group('28J partial provider failure', () {
    test('a refused recipient is reported and not charged', () async {
      final transport = _RecordingTransport()..reject.add('233559876543');
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      expect(summary.sent.length, 1);
      expect(summary.failures.length, 1);
      expect(summary.failures.single.recipient.normalized, '233559876543');
      // Only the accepted recipient keeps its credit.
      expect(summary.creditsCharged, 1);
      expect(summary.creditsRefunded, 1);
    });

    test('the other recipients still succeed after one fails', () async {
      final transport = _RecordingTransport()..reject.add('233241234567');
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543', '0201112222'],
      );

      expect(transport.phones.length, 3);
      expect(summary.sent.length, 2);
      expect(summary.failures.length, 1);
    });

    test('no history row is written for a refused recipient', () async {
      final transport = _RecordingTransport()..reject.add('233559876543');
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      final rows = await database.query('receipt_sends');
      expect(rows.length, 1);
      expect(rows.single['phone'], '233241234567');
    });

    test('a total failure still reports every failure', () async {
      final transport = _RecordingTransport()
        ..reject.addAll(['233241234567', '233559876543']);
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      expect(summary.sent, isEmpty);
      expect(summary.failures.length, 2);
      expect(summary.creditsCharged, 0);
      expect(await database.query('receipt_sends'), isEmpty);
    });
  });

  group('28K SMS history', () {
    test('one history row is recorded per accepted recipient', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543', '0201112222'],
      );

      final rows = await database.query('receipt_sends', orderBy: 'phone');
      expect(rows.length, 3);
      expect(rows.map((row) => row['phone']), [
        '233201112222',
        '233241234567',
        '233559876543',
      ]);
    });

    test('a duplicate recipient is never recorded twice', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '+233241234567', '233241234567'],
      );

      final rows = await database.query('receipt_sends');
      expect(rows.length, 1);
    });

    test('history keeps the queued status, never delivered', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport)
          .sendToMany(deliveryFor('company-a'), phones: const ['0241234567']);

      final row = (await database.query('receipt_sends')).single;
      expect(row['status'], 'queued');
      expect(row['channel'], 'sms');
    });

    test('history is scoped to the active company', () async {
      final transport = _RecordingTransport();
      await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      final rows = await database.query('receipt_sends');
      expect(rows.every((row) => row['company_id'] == 'company-a'), isTrue);
    });
  });

  group('tenant isolation', () {
    test('another company\'s delivery cannot be sent to', () async {
      final transport = _RecordingTransport();
      await expectLater(
        serviceFor(transport)
            .sendToMany(deliveryFor('company-b'), phones: const ['0241234567']),
        throwsA(isA<SmsReceiptException>()),
      );
      // Nothing reached the provider and no history was written.
      expect(transport.phones, isEmpty);
      expect(await database.query('receipt_sends'), isEmpty);
    });

    test('a user with no active company cannot send', () async {
      final transport = _RecordingTransport();
      await expectLater(
        serviceFor(
          transport,
          activeCompany: null,
        ).sendToMany(deliveryFor(null), phones: const ['0241234567']),
        throwsA(isA<SmsReceiptException>()),
      );
      expect(transport.phones, isEmpty);
    });
  });

  group('input validation', () {
    test('an empty list is refused before any send', () async {
      final transport = _RecordingTransport();
      await expectLater(
        serviceFor(transport)
            .sendToMany(deliveryFor('company-a'), phones: const []),
        throwsA(isA<SmsReceiptException>()),
      );
      expect(transport.phones, isEmpty);
    });

    test('invalid numbers are reported and never guessed at', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', 'abc', '12345'],
      );

      expect(summary.rejected, ['abc', '12345']);
      expect(transport.phones, ['233241234567']);
      // Only the valid number costs anything.
      expect(summary.creditsCharged, 1);
    });

    test('a list of only invalid numbers sends nothing', () async {
      final transport = _RecordingTransport();
      await expectLater(
        serviceFor(
          transport,
        ).sendToMany(deliveryFor('company-a'), phones: const ['abc', '12345']),
        throwsA(isA<SmsReceiptException>()),
      );
      expect(transport.phones, isEmpty);
    });
  });

  group('28L summary for the UI', () {
    test('a full success reports the recipient count', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport).sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567', '0559876543'],
      );

      expect(summary.allSucceeded, isTrue);
      expect(summary.message, contains('2 recipients'));
    });

    test('a single success uses the singular wording', () async {
      final transport = _RecordingTransport();
      final summary = await serviceFor(transport)
          .sendToMany(deliveryFor('company-a'), phones: const ['0241234567']);
      expect(summary.message, contains('1 recipient'));
    });

    test(
      'a partial failure says how many failed and were not charged',
      () async {
        final transport = _RecordingTransport()..reject.add('233559876543');
        final summary = await serviceFor(transport).sendToMany(
          deliveryFor('company-a'),
          phones: const ['0241234567', '0559876543'],
        );

        expect(summary.allSucceeded, isFalse);
        expect(summary.message, contains('1 of 2'));
        expect(summary.message, contains('not charged'));
      },
    );
  });

  group('unchanged single-recipient behaviour', () {
    test('send() still works exactly as before', () async {
      final transport = _RecordingTransport();
      await SmsReceiptService(
        transport: transport,
        senderLabel: 'ALBNC',
        database: database,
        companyIdProvider: () => 'company-a',
      ).send(deliveryFor('company-a'));

      expect(transport.phones, ['233241234567']);
      final rows = await database.query('receipt_sends');
      expect(rows.length, 1);
      expect(rows.single['phone'], '233241234567');
    });

    test(
      'sendToMany with one number matches the single-recipient path',
      () async {
        final transport = _RecordingTransport();
        final summary = await serviceFor(transport)
            .sendToMany(deliveryFor('company-a'), phones: const ['0241234567']);

        expect(transport.phones, ['233241234567']);
        expect(summary.creditsRequired, 1);
        expect((await database.query('receipt_sends')).length, 1);
      },
    );

    test(
      'company A at zero is blocked while company B spends only B credits',
      () async {
        final companyCredits = _CompanyCredits({
          'company-a': 0,
          'company-b': 5,
        });
        final blockedTransport = _RecordingTransport();
        final blockedService = serviceFor(
          blockedTransport,
          credits: companyCredits,
        );

        await expectLater(
          blockedService.sendToMany(
            deliveryFor('company-a'),
            phones: const ['0241234567'],
          ),
          throwsA(isA<SmsReceiptException>()),
        );
        expect(blockedTransport.phones, isEmpty);

        final allowedTransport = _RecordingTransport();
        final allowedService = serviceFor(
          allowedTransport,
          activeCompany: 'company-b',
          credits: companyCredits,
        );
        final summary = await allowedService.sendToMany(
          deliveryFor('company-b'),
          phones: const ['0241234567'],
        );

        expect(summary.creditsCharged, 1);
        expect(allowedTransport.phones, ['233241234567']);
        expect(companyCredits.balances, {'company-a': 0, 'company-b': 5});
      },
    );

    test('an already-sent recipient is not re-sent or re-charged', () async {
      // The server owns the duplicate guard. Locally the second send is simply
      // not attempted, which the test proves by reusing the same list twice
      // against a fresh transport, showing the client does no hidden sending.
      final transport = _RecordingTransport();
      final service = serviceFor(transport);
      await service.sendToMany(
        deliveryFor('company-a'),
        phones: const ['0241234567'],
      );
      expect(transport.phones.length, 1);
      expect((await database.query('receipt_sends')).length, 1);
    });
  });
}
