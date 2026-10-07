import 'dart:async';
import 'dart:convert';

import 'package:flutter_application_2/domain/models/delivery.dart';
import 'package:flutter_application_2/domain/models/product.dart';
import 'package:flutter_application_2/domain/models/supplier.dart';
import 'package:flutter_application_2/features/receiving/delivery_repository.dart';
import 'package:flutter_application_2/features/sync/supabase_delivery_store.dart';
import 'package:flutter_application_2/features/sync/sync_coordinator.dart';
import 'package:flutter_application_2/features/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SyncGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _GatedDeliveryRepository extends DeliveryRepository {
  _GatedDeliveryRepository(
    super.database, {
    required super.companyIdProvider,
    this.recordGate,
  }) : super(userIdProvider: () => 'user-a');

  final _SyncGate? recordGate;

  @override
  Future<void> recordSyncAttemptForScope(
    String id,
    DateTime attemptedAt,
    SyncScope scope,
  ) async {
    final gate = recordGate;
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
    }
    await super.recordSyncAttemptForScope(id, attemptedAt, scope);
  }
}

class _MismatchedQueueRepository extends DeliveryRepository {
  _MismatchedQueueRepository(
    super.database, {
    required super.companyIdProvider,
    required this.queuedDelivery,
  }) : super(userIdProvider: () => 'user-a');

  final Delivery queuedDelivery;

  @override
  Future<List<Delivery>> unsynchronizedForScope(SyncScope scope) async =>
      [queuedDelivery];
}

class _RecordingRemoteStore implements CompanyCatalogStore {
  _RecordingRemoteStore({this.uploadGate, this.failedIds = const {}});

  final _SyncGate? uploadGate;
  final Set<String> failedIds;
  final supplierCompanies = <String>[];
  final productCompanies = <String>[];
  final deliveryCompanies = <String>[];
  final bagWeightCompanies = <String>[];
  final uploadScopes = <SyncScope>[];
  final catalogScopes = <SyncScope>[];
  final downloadScopes = <SyncScope>[];

  @override
  Future<void> synchronizeCatalog({required SyncScope scope}) async {
    catalogScopes.add(scope);
  }

  @override
  Future<void> downloadCompany({required SyncScope scope}) async {
    downloadScopes.add(scope);
  }

  @override
  Future<void> upsert(Delivery delivery, {required SyncScope scope}) async {
    uploadScopes.add(scope);
    final gate = uploadGate;
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
    }
    if (failedIds.contains(delivery.id)) {
      throw StateError('upload failed');
    }
    final companyId = scope.companyId;
    if (companyId == null) throw StateError('sync scope has no company');
    supplierCompanies.add(companyId);
    productCompanies.add(companyId);
    deliveryCompanies.add(companyId);
    if (!delivery.isBulk) {
      bagWeightCompanies.addAll(
        List.filled(delivery.bagWeights.length, companyId),
      );
    }
  }
}

void main() {
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(':memory:');
    await database.execute('''
      CREATE TABLE suppliers (
        supplier_id TEXT NOT NULL,
        company_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        supplier_type TEXT NOT NULL DEFAULT 'farmer',
        normalized_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (company_id, supplier_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE deliveries (
        id TEXT PRIMARY KEY,
        company_id TEXT,
        supplier_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        recorded_by_user_id TEXT,
        status TEXT NOT NULL,
        synchronization_status TEXT NOT NULL,
        supplier_name TEXT NOT NULL,
        product_name TEXT NOT NULL,
        supplier_type TEXT NOT NULL,
        synchronization_error TEXT,
        sync_attempts INTEGER NOT NULL DEFAULT 0,
        last_sync_attempt_at TEXT,
        synced_at TEXT,
        record_type TEXT NOT NULL DEFAULT 'individual',
        total_weight REAL,
        bag_count INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE delivery_bag_weights (
        delivery_id TEXT NOT NULL,
        company_id TEXT,
        bag_number INTEGER NOT NULL,
        weight REAL NOT NULL,
        recorded_by_user_id TEXT,
        PRIMARY KEY (company_id, delivery_id, bag_number)
      )
    ''');
  });

  tearDown(() => database.close());

  test('normal sync uploads an A delivery only to company A', () async {
    var activeCompanyId = 'company-a';
    final repository = DeliveryRepository(
      database,
      companyIdProvider: () => activeCompanyId,
      userIdProvider: () => 'user-a',
    );
    await repository.save(_delivery('a-normal', 'company-a'));
    final remote = _RecordingRemoteStore();
    final coordinator = SyncCoordinator(
      database: database,
      deliveryRepository: repository,
      remoteStore: remote,
    );

    final summary = await coordinator.synchronize();

    expect(summary.synced, 1);
    expect(remote.supplierCompanies, ['company-a']);
    expect(remote.productCompanies, ['company-a']);
    expect(remote.deliveryCompanies, ['company-a']);
    expect(remote.bagWeightCompanies, ['company-a', 'company-a']);
    expect(remote.catalogScopes.single.companyId, 'company-a');
    expect(remote.downloadScopes.single.companyId, 'company-a');
    expect(activeCompanyId, 'company-a');
  });

  test('switch before upload keeps queue and local status bound to A', () async {
    var activeCompanyId = 'company-a';
    final recordGate = _SyncGate();
    final repository = _GatedDeliveryRepository(
      database,
      companyIdProvider: () => activeCompanyId,
      recordGate: recordGate,
    );
    await repository.save(_delivery('a-before-switch', 'company-a'));
    final companyBRepository = DeliveryRepository(
      database,
      companyIdProvider: () => 'company-b',
      userIdProvider: () => 'user-b',
    );
    await companyBRepository.save(_delivery('b-remains-pending', 'company-b'));
    final remote = _RecordingRemoteStore();
    final coordinator = SyncCoordinator(
      database: database,
      deliveryRepository: repository,
      remoteStore: remote,
    );

    final runningSync = coordinator.synchronize();
    await recordGate.entered.future;
    activeCompanyId = 'company-b';
    final concurrent = await coordinator.synchronize();
    expect(concurrent.attempted, 0);
    recordGate.release.complete();
    final summary = await runningSync;

    expect(summary.synced, 1);
    expect(remote.uploadScopes.single.companyId, 'company-a');
    expect(remote.supplierCompanies, ['company-a']);
    expect(remote.deliveryCompanies, ['company-a']);
    expect(remote.bagWeightCompanies, ['company-a', 'company-a']);
    final rows = await database.query('deliveries', orderBy: 'id');
    expect(
      rows.map((row) => '${row['company_id']}:${row['synchronization_status']}'),
      ['company-a:synced', 'company-b:pending'],
    );
  });

  test('a queued delivery from B is rejected in an A sync before side effects',
      () async {
    var activeCompanyId = 'company-a';
    final repository = _MismatchedQueueRepository(
      database,
      companyIdProvider: () => activeCompanyId,
      queuedDelivery: _delivery('b-mismatch', 'company-b'),
    );
    final remote = _RecordingRemoteStore();
    final coordinator = SyncCoordinator(
      database: database,
      deliveryRepository: repository,
      remoteStore: remote,
    );

    final summary = await coordinator.synchronize();

    expect(summary.failed, 1);
    expect(summary.failures.single.message, contains('does not match'));
    expect(remote.uploadScopes, isEmpty);
    expect(remote.supplierCompanies, isEmpty);
    expect(remote.productCompanies, isEmpty);
    expect(remote.deliveryCompanies, isEmpty);
    expect(remote.bagWeightCompanies, isEmpty);
    expect(activeCompanyId, 'company-a');
  });

  test('switch after upload starts cannot retarget the captured scope', () async {
    var activeCompanyId = 'company-a';
    final repository = DeliveryRepository(
      database,
      companyIdProvider: () => activeCompanyId,
      userIdProvider: () => 'user-a',
    );
    await repository.save(_delivery('a-in-flight', 'company-a'));
    final uploadGate = _SyncGate();
    final remote = _RecordingRemoteStore(uploadGate: uploadGate);
    final coordinator = SyncCoordinator(
      database: database,
      deliveryRepository: repository,
      remoteStore: remote,
    );

    final runningSync = coordinator.synchronize();
    await uploadGate.entered.future;
    activeCompanyId = 'company-b';
    uploadGate.release.complete();
    final summary = await runningSync;

    expect(summary.synced, 1);
    expect(remote.uploadScopes.single.companyId, 'company-a');
    expect(remote.supplierCompanies, ['company-a']);
    expect(remote.productCompanies, ['company-a']);
    expect(remote.deliveryCompanies, ['company-a']);
    expect(remote.bagWeightCompanies, ['company-a', 'company-a']);
    expect((await database.query('deliveries')).single['synchronization_status'], 'synced');
  });

  test('failed in-flight A upload marks only the A local row failed', () async {
    var activeCompanyId = 'company-a';
    final repository = DeliveryRepository(
      database,
      companyIdProvider: () => activeCompanyId,
      userIdProvider: () => 'user-a',
    );
    await repository.save(_delivery('a-failed', 'company-a'));
    final companyBRepository = DeliveryRepository(
      database,
      companyIdProvider: () => 'company-b',
      userIdProvider: () => 'user-b',
    );
    await companyBRepository.save(_delivery('b-stays-pending', 'company-b'));
    final uploadGate = _SyncGate();
    final remote = _RecordingRemoteStore(
      uploadGate: uploadGate,
      failedIds: const {'a-failed'},
    );
    final coordinator = SyncCoordinator(
      database: database,
      deliveryRepository: repository,
      remoteStore: remote,
    );

    final runningSync = coordinator.synchronize();
    await uploadGate.entered.future;
    activeCompanyId = 'company-b';
    uploadGate.release.complete();
    final summary = await runningSync;

    expect(summary.failed, 1);
    final rows = await database.query('deliveries', orderBy: 'id');
    expect(
      rows.map((row) => '${row['company_id']}:${row['synchronization_status']}'),
      ['company-a:syncFailed', 'company-b:pending'],
    );
  });

  test('Supabase store rejects mismatched delivery before network writes',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );
    final store = SupabaseDeliveryStore(
      client,
      localDatabase: database,
      userId: () => 'user-a',
      isAdmin: () => true,
    );

    await expectLater(
      store.upsert(
        _delivery('b-invalid', 'company-b'),
        scope: const SyncScope(companyId: 'company-a', isCompanyScoped: true),
      ),
      throwsA(isA<StateError>()),
    );

    expect(requests, isEmpty);
    await client.dispose();
  });

  test('Supabase store keeps all writes on captured A after context switches',
      () async {
    var activeCompanyId = 'company-a';
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'POST' && path.endsWith('/suppliers')) {
          activeCompanyId = 'company-b';
          return http.Response(
            '{}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST') {
          return http.Response(
            '{}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/products')) {
          return http.Response(
            jsonEncode({'id': 'cashew'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/deliveries') &&
            request.url.queryParameters['select'] == 'record_type') {
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }
        if (path.endsWith('/deliveries')) {
          return http.Response(
            jsonEncode({
              'updated_at': '2026-09-21T00:00:00.000',
              'recorded_by_user_id': 'user-a',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/delivery_bag_weights')) {
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    final store = SupabaseDeliveryStore(
      client,
      localDatabase: database,
      userId: () => 'user-a',
      isAdmin: () => true,
    );
    const scope = SyncScope(companyId: 'company-a', isCompanyScoped: true);

    await store.upsert(_delivery('a-real-store', 'company-a'), scope: scope);

    expect(activeCompanyId, 'company-b');
    for (final request in requests) {
      expect(request.url.queryParameters['company_id'], isNot('eq.company-b'));
      if (request.method == 'POST') {
        final payload = jsonDecode(request.body);
        final rows = payload is List ? payload : [payload];
        expect(
          rows.every((row) => row['company_id'] == 'company-a'),
          isTrue,
          reason: 'Every supplier, delivery, and bag write must stay in A.',
        );
      }
    }
    expect(
      requests.where((request) => request.method == 'POST'),
      isNotEmpty,
    );
    await client.dispose();
  });
}

Delivery _delivery(String id, String companyId) {
  return Delivery(
    id: id,
    supplier: Supplier(
      id: 'supplier-1',
      companyId: companyId,
      name: 'Kofi Mensah',
      type: SupplierType.farmer,
      town: 'A town',
      district: 'A district',
      region: 'A region',
    ),
    product: Product(id: 'cashew', name: 'Cashew', companyId: companyId),
    recordedAt: DateTime(2026, 9, 21),
    bagWeights: const [10, 20],
    recordedByUserId: companyId == 'company-a' ? 'user-a' : 'user-b',
    companyId: companyId,
  );
}