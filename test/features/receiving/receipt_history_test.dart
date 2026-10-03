import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Receipt history / search / proof tests.
///
/// The delivery record is the single source of truth. These tests confirm a
/// saved receipt can be found, opened and reprinted without ever creating a
/// duplicate record, and that history is restricted to the user's own company.
void main() {
  late Database database;
  late DeliveryRepository repository;
  String activeCompany = 'company-a';

  final recordedAt = DateTime(2026, 9, 20, 9, 30);

  Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE deliveries (
        id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        recorded_by_user_id TEXT,
        company_id TEXT,
        status TEXT NOT NULL,
        synchronization_status TEXT NOT NULL,
        supplier_name TEXT NOT NULL,
        product_name TEXT NOT NULL,
        supplier_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE delivery_bag_weights (
        delivery_id TEXT NOT NULL,
        company_id TEXT,
        bag_number INTEGER NOT NULL,
        weight REAL NOT NULL,
        recorded_by_user_id TEXT,
        PRIMARY KEY (delivery_id, bag_number)
      )
    ''');
    await db.execute('''
      CREATE TABLE suppliers (
        internal_id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        company_id TEXT,
        normalized_name TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        phone TEXT,
        town TEXT NOT NULL DEFAULT '',
        district TEXT NOT NULL DEFAULT '',
        region TEXT NOT NULL DEFAULT '',
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synchronization_status TEXT NOT NULL DEFAULT 'pendingSync',
        synchronization_error TEXT
      )
    ''');
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
  }

  Future<void> insertSupplier({
    required String companyId,
    required String supplierId,
    required String name,
    String? phone,
  }) async {
    await database.insert('suppliers', {
      'internal_id': 'int-$companyId-$supplierId',
      'supplier_id': supplierId,
      'company_id': companyId,
      'normalized_name': name.toLowerCase(),
      'name': name,
      'type': 'farmer',
      'phone': phone,
      'created_at': DateTime(2026, 9, 20).toIso8601String(),
      'updated_at': DateTime(2026, 9, 20).toIso8601String(),
    });
  }

  Future<void> insertDelivery({
    required String id,
    required String companyId,
    required String supplierId,
    required String supplierName,
    required String recordedBy,
    required DateTime recordedAt,
    List<double> weights = const [25, 30, 20],
  }) async {
    await database.insert('deliveries', {
      'id': id,
      'supplier_id': supplierId,
      'product_id': 'cashew',
      'recorded_at': recordedAt.toIso8601String(),
      'recorded_by_user_id': recordedBy,
      'company_id': companyId,
      'status': 'received',
      'synchronization_status': 'synced',
      'supplier_name': supplierName,
      'product_name': 'Cashew',
      'supplier_type': 'farmer',
      'created_at': recordedAt.toIso8601String(),
      'updated_at': recordedAt.toIso8601String(),
    });
    for (var i = 0; i < weights.length; i++) {
      await database.insert('delivery_bag_weights', {
        'delivery_id': id,
        'company_id': companyId,
        'bag_number': i + 1,
        'weight': weights[i],
        'recorded_by_user_id': recordedBy,
      });
    }
  }

  Future<void> recordSms(
    String id,
    String deliveryId,
    String companyId,
    String status, {
    String? providerReference,
  }) async {
    await database.insert('receipt_sends', {
      'id': id,
      'delivery_id': deliveryId,
      'company_id': companyId,
      'phone': '233241234567',
      'channel': 'sms',
      'status': status,
      'sent_at': DateTime(2026, 9, 20, 10).toIso8601String(),
      'provider_reference': providerReference,
    });
  }

  setUp(() async {
    // The active company is shared mutable state that a test may switch (for
    // example to prove company isolation), so it is restored here. Without this
    // reset the switch leaks into every later test and they all query as the
    // wrong tenant.
    activeCompany = 'company-a';
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => createSchema(db),
      ),
    );
    repository = DeliveryRepository(
      database,
      companyIdProvider: () => activeCompany,
      userIdProvider: () => 'secretary-1',
    );
    await insertSupplier(
      companyId: 'company-a',
      supplierId: 'ALB-1',
      name: 'Abdul Wahid',
      phone: '0241234567',
    );
    await insertSupplier(
      companyId: 'company-b',
      supplierId: 'ALB-9',
      name: 'Other Traders',
      phone: '0209998888',
    );
    await insertDelivery(
      id: 'TXN-00125',
      companyId: 'company-a',
      supplierId: 'ALB-1',
      supplierName: 'Abdul Wahid',
      recordedBy: 'secretary-1',
      recordedAt: recordedAt,
    );
    await insertDelivery(
      id: 'TXN-00126',
      companyId: 'company-a',
      supplierId: 'ALB-1',
      supplierName: 'Abdul Wahid',
      recordedBy: 'secretary-2',
      recordedAt: recordedAt.add(const Duration(days: 1)),
      weights: const [10, 15],
    );
    await insertDelivery(
      id: 'TXN-00999',
      companyId: 'company-b',
      supplierId: 'ALB-9',
      supplierName: 'Other Traders',
      recordedBy: 'secretary-9',
      recordedAt: recordedAt,
    );
  });

  tearDown(() => database.close());

  group('historical receipt search', () {
    test('finds a historical receipt by its identifier', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(query: 'TXN-00125'),
      );
      expect(results.map((d) => d.id), ['TXN-00125']);
    });

    test('finds a historical receipt by supplier name', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(query: 'abdul'),
      );
      expect(results.map((d) => d.id), containsAll(['TXN-00125', 'TXN-00126']));
    });

    test('finds a historical receipt by phone number', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(phone: '0241234567'),
      );
      expect(results, hasLength(2));
      expect(
        results.every((d) => d.supplier.id == 'ALB-1'),
        isTrue,
        reason: 'phone search must resolve through the saved supplier',
      );
    });

    test('finds historical receipts by date range', () async {
      final results = await repository.search(
        ReceiptSearchFilters(
          from: DateTime(2026, 9, 21),
          to: DateTime(2026, 9, 22),
        ),
      );
      expect(results.map((d) => d.id), ['TXN-00126']);
    });

    test('finds historical receipts by secretary', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(recorderUserId: 'secretary-2'),
      );
      expect(results.map((d) => d.id), ['TXN-00126']);
    });

    test('an unrelated search term returns nothing', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(query: 'no-such-receipt'),
      );
      expect(results, isEmpty);
    });
  });

  group('historical receipt content and proof', () {
    test('displays all original bag weights', () async {
      final receipt = await repository.findById('TXN-00125');
      expect(receipt, isNotNull);
      expect(receipt!.bagWeights, [25.0, 30.0, 20.0]);
    });

    test('displays the correct bag count and total weight', () async {
      final receipt = await repository.findById('TXN-00125');
      expect(receipt!.numberOfBags, 3);
      expect(receipt.totalWeight, 75.0);
    });

    test('preserves the recorder and date exactly as recorded', () async {
      final receipt = await repository.findById('TXN-00125');
      expect(receipt!.recordedByUserId, 'secretary-1');
      expect(receipt.bagRecordedByUserIds, everyElement('secretary-1'));
      expect(receipt.recordedAt, recordedAt);
    });

    test('carries the saved supplier phone for reprint and SMS', () async {
      final receipt = await repository.findById('TXN-00125');
      expect(receipt!.supplier.phone, '0241234567');
    });

    test('reopening and reprinting does not create a duplicate record', () async {
      final before = await database.query('deliveries');
      // Reading the saved receipt is what printing uses; it must not write.
      final first = await repository.findById('TXN-00125');
      final second = await repository.findById('TXN-00125');
      final after = await database.query('deliveries');
      expect(first!.bagWeights, second!.bagWeights);
      expect(after, hasLength(before.length));
      expect(after.map((r) => r['id']).toSet(), hasLength(before.length));
    });
  });

  group('company isolation for receipt history', () {
    test('search only returns the active company receipts', () async {
      final results = await repository.search(const ReceiptSearchFilters());
      expect(
        results.map((d) => d.id),
        isNot(contains('TXN-00999')),
        reason: 'Company B receipt must never appear for Company A',
      );
    });

    test('a receipt from another company cannot be opened', () async {
      expect(await repository.findById('TXN-00999'), isNull);
    });

    test('another company cannot be reached by its receipt number', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(query: 'TXN-00999'),
      );
      expect(results, isEmpty);
    });

    test('phone search cannot reach another company supplier', () async {
      final results = await repository.search(
        const ReceiptSearchFilters(phone: '0209998888'),
      );
      expect(results, isEmpty);
    });

    test('switching company shows only that company receipts', () async {
      activeCompany = 'company-b';
      final results = await repository.search(const ReceiptSearchFilters());
      expect(results.map((d) => d.id), ['TXN-00999']);
      expect(await repository.findById('TXN-00125'), isNull);
    });
  });

  group('receipt SMS history', () {
    test('reports not sent when there is no SMS record', () async {
      final statuses = await repository.receiptSmsFor(['TXN-00125']);
      expect(statuses, isEmpty);
    });

    test('a provider 202 is reported as queued, never as delivered', () async {
      await recordSms(
        'sms-1',
        'TXN-00125',
        'company-a',
        'queued',
        providerReference: 'sailup-msg-1',
      );
      final record = (await repository.receiptSmsFor([
        'TXN-00125',
      ]))['TXN-00125']!;
      expect(record.label, 'Queued');
      expect(record.isQueued, isTrue);
      expect(record.isDelivered, isFalse);
      expect(record.providerReference, 'sailup-msg-1');
    });

    test('only a confirmed delivery reports Sent', () async {
      await recordSms('sms-2', 'TXN-00125', 'company-a', 'sent');
      final record = (await repository.receiptSmsFor([
        'TXN-00125',
      ]))['TXN-00125']!;
      expect(record.label, 'Sent');
      expect(record.isDelivered, isTrue);
    });

    test('a failed attempt reports Failed', () async {
      await recordSms('sms-3', 'TXN-00125', 'company-a', 'failed');
      final record = (await repository.receiptSmsFor([
        'TXN-00125',
      ]))['TXN-00125']!;
      expect(record.label, 'Failed');
      expect(record.isDelivered, isFalse);
    });

    test('does not expose another company SMS history', () async {
      await recordSms('sms-4', 'TXN-00999', 'company-b', 'queued');
      final statuses = await repository.receiptSmsFor(['TXN-00999']);
      expect(statuses, isEmpty);
    });

    test('an SMS retry does not create a duplicate receipt', () async {
      final before = await database.query('deliveries');
      await recordSms('sms-retry-1', 'TXN-00125', 'company-a', 'queued');
      await recordSms('sms-retry-2', 'TXN-00125', 'company-a', 'queued');
      final after = await database.query('deliveries');
      expect(after, hasLength(before.length));
      // Only the latest attempt is surfaced for the receipt.
      final statuses = await repository.receiptSmsFor(['TXN-00125']);
      expect(statuses, hasLength(1));
    });
  });
}
