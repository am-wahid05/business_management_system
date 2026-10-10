import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_application_2/features/analytics/analytics_models.dart';
import 'package:flutter_application_2/features/analytics/analytics_repository.dart';
import 'package:flutter_application_2/features/analytics/weekly_purchasing_intelligence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final testPythonExecutable =
      Platform.environment['WEEKLY_PURCHASING_TEST_PYTHON'];
  final testPythonScript = Platform.environment[
    'WEEKLY_PURCHASING_TEST_PYTHON_SCRIPT'
  ];
  late Database database;
  late AnalyticsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE deliveries (
              id TEXT NOT NULL, company_id TEXT, supplier_id TEXT NOT NULL, product_id TEXT NOT NULL,
              recorded_at TEXT NOT NULL, recorded_by_user_id TEXT NOT NULL, status TEXT NOT NULL,
              synchronization_status TEXT NOT NULL, supplier_internal_id TEXT,
              supplier_name TEXT NOT NULL, product_name TEXT NOT NULL, supplier_type TEXT NOT NULL,
              record_type TEXT NOT NULL DEFAULT 'individual', total_weight REAL, bag_count INTEGER,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              PRIMARY KEY (company_id, id)
            )
          ''');
          await database.execute('''
            CREATE TABLE delivery_bag_weights (
              delivery_id TEXT NOT NULL, company_id TEXT, bag_number INTEGER NOT NULL, weight REAL NOT NULL,
              PRIMARY KEY (company_id, delivery_id, bag_number)
            )
          ''');
          await database.execute('''
            CREATE TABLE suppliers (
              internal_id TEXT PRIMARY KEY, company_id TEXT, supplier_id TEXT NOT NULL,
              normalized_name TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
              phone TEXT, town TEXT NOT NULL, district TEXT NOT NULL, region TEXT NOT NULL,
              notes TEXT, is_active INTEGER NOT NULL, created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL, synchronization_status TEXT NOT NULL,
              synchronization_error TEXT
            )
          ''');
        },
      ),
    );
    repository = AnalyticsRepository(
      database,
      companyIdProvider: () => 'tenant-a',
    );

    await _insertSupplier(
      database,
      'supplier-a-1',
      'ALB-000001',
      'Alpha Supplier',
      'farmer',
      'Town A',
      true,
      companyId: 'tenant-a',
    );
    await _insertSupplier(
      database,
      'supplier-b-1',
      'ALB-000020',
      'Beta Supplier',
      'farmer',
      'Town B',
      true,
      companyId: 'tenant-b',
    );

    final today = DateTime(2026, 9, 30);
    final week1 = DateTime(2026, 9, 28);
    final week2 = DateTime(2026, 9, 21);

    await _insertDelivery(
      database,
      'd1',
      'ALB-000001',
      'cashew',
      'Cashew',
      'farmer',
      '${week1.toIso8601String()}T10:00:00',
      [120, 80],
      companyId: 'tenant-a',
    );
    await _insertDelivery(
      database,
      'd2',
      'ALB-000001',
      'cocoa',
      'Cocoa',
      'farmer',
      '${week1.toIso8601String()}T11:00:00',
      [90],
      companyId: 'tenant-a',
    );
    await _insertDelivery(
      database,
      'd3',
      'ALB-000001',
      'cashew',
      'Cashew',
      'farmer',
      '${week2.toIso8601String()}T12:00:00',
      [60],
      companyId: 'tenant-a',
    );
    await _insertDelivery(
      database,
      'd4',
      'ALB-000020',
      'cocoa',
      'Cocoa',
      'farmer',
      '${week2.toIso8601String()}T13:00:00',
      [500],
      companyId: 'tenant-b',
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'buildWeeklySnapshot creates the required schema-version-1 JSON contract',
    () async {
      final service = WeeklyPurchasingIntelligenceService(
        analyticsRepository: repository,
        pythonExecutable: 'python',
        pythonScriptPath: 'weekly_purchasing_intelligence.py',
      );

      final snapshot = await service.buildWeeklySnapshot(
        endDate: DateTime(2026, 9, 30),
        weeks: 2,
      );

      expect(snapshot['schema_version'], 1);
      expect(snapshot['weeks'], isA<List>());
      expect(snapshot['weeks'], hasLength(2));

      final firstWeek = snapshot['weeks'][0] as Map<String, dynamic>;
      expect(firstWeek['week_start'], '2026-09-21');
      expect(firstWeek['products'], isA<Map>());
      expect(firstWeek['products']['cashew'], 60.0);
      expect(firstWeek['products']['cocoa'] ?? 0.0, 0.0);

      final secondWeek = snapshot['weeks'][1] as Map<String, dynamic>;
      expect(secondWeek['week_start'], '2026-09-28');
      expect(secondWeek['products']['cashew'], 200.0);
      expect(secondWeek['products']['cocoa'], 90.0);
    },
  );

  test('analyzeWeeklyPurchasing validates malformed Python output', () async {
    final service = WeeklyPurchasingIntelligenceService(
      analyticsRepository: repository,
      pythonExecutable: 'python',
      pythonScriptPath: 'weekly_purchasing_intelligence.py',
      processRunner:
          (
            _,
            __, {
            required String stdinText,
            String? workingDirectory,
            Map<String, String>? environment,
          }) async {
            return ProcessResult(123, 0, '{not-json', '');
          },
    );

    expect(
      () => service.analyzeWeeklyPurchasing(
        endDate: DateTime(2026, 9, 30),
        weeks: 2,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('analyzeWeeklyPurchasing throws on Python process failure', () async {
    final service = WeeklyPurchasingIntelligenceService(
      analyticsRepository: repository,
      pythonExecutable: 'python',
      pythonScriptPath: 'weekly_purchasing_intelligence.py',
      processRunner:
          (
            _,
            __, {
            required String stdinText,
            String? workingDirectory,
            Map<String, String>? environment,
          }) async {
            return ProcessResult(123, 1, '', 'python crashed');
          },
    );

    expect(
      () => service.analyzeWeeklyPurchasing(
        endDate: DateTime(2026, 9, 30),
        weeks: 2,
      ),
      throwsA(isA<ProcessException>()),
    );
  });

  test(
    'analyzeWeeklyPurchasing requires a configured Python runtime',
    () async {
      final service = WeeklyPurchasingIntelligenceService(
        analyticsRepository: repository,
        pythonExecutable: '',
        pythonScriptPath: '',
      );

      expect(
        () => service.analyzeWeeklyPurchasing(
          endDate: DateTime(2026, 9, 30),
          weeks: 2,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('bundled runtime paths resolve beside the Windows application', () {
    final paths = WeeklyPurchasingPythonPaths.resolve(
      isWindows: true,
      applicationExecutablePath:
          r'C:\Program Files\AL-BNC\business_management_system.exe',
    );

    expect(
      paths.executable,
      p.join(r'C:\Program Files\AL-BNC', 'python', 'python.exe'),
    );
    expect(
      paths.script,
      p.join(
        r'C:\Program Files\AL-BNC',
        'python',
        'weekly_purchasing_intelligence.py',
      ),
    );
  });

  test('missing bundled files report runtime unavailable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'weekly-purchasing-missing-runtime-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = WeeklyPurchasingIntelligenceService(
      analyticsRepository: repository,
      pythonExecutable: p.join(directory.path, 'python.exe'),
      pythonScriptPath: p.join(directory.path, 'weekly.py'),
    );

    expect(service.isRuntimeConfigured, isFalse);
    await expectLater(
      service.analyzeWeeklyPurchasing(endDate: DateTime(2026, 9, 30)),
      throwsA(isA<StateError>()),
    );
  });

  test('analyzeWeeklyPurchasing returns the Python JSON result when execution succeeds', () async {
    final service = WeeklyPurchasingIntelligenceService(
      analyticsRepository: repository,
      pythonExecutable: 'python',
      pythonScriptPath: 'weekly_purchasing_intelligence.py',
      processRunner:
          (
            _,
            __, {
            required String stdinText,
            String? workingDirectory,
            Map<String, String>? environment,
          }) async {
            final decoded = jsonDecode(stdinText) as Map<String, dynamic>;
            expect(decoded['schema_version'], 1);
            final firstWeek = decoded['weeks'][0] as Map<String, dynamic>;
            expect(firstWeek['products']['cashew'], 60.0);
            final secondWeek = decoded['weeks'][1] as Map<String, dynamic>;
            expect(secondWeek['products']['cocoa'], 90.0);
            return ProcessResult(
              42,
              0,
              jsonEncode({
                'schema_version': 1,
                'method': 'ok',
                'weekly_totals': [
                  {'week_start': '2026-09-21', 'total_weight': 60.0},
                  {'week_start': '2026-09-28', 'total_weight': 290.0},
                ],
                'latest_week': {
                  'week_start': '2026-09-28',
                  'total_weight': 290.0,
                  'week_over_week_percent': 383.33,
                },
                'products': [],
              }),
              '',
            );
          },
    );

    final result = await service.analyzeWeeklyPurchasing(
      endDate: DateTime(2026, 9, 30),
      weeks: 2,
    );

    expect(result['schema_version'], 1);
    expect(result['method'], 'ok');
    expect(result['latest_week']['total_weight'], 290.0);
  });

  test(
    'runs Python end to end with the active-company aggregate snapshot',
    () async {
      final service = WeeklyPurchasingIntelligenceService(
        analyticsRepository: repository,
        pythonExecutable: testPythonExecutable,
        pythonScriptPath:
            testPythonScript ??
            p.join(
              Directory.current.path,
              'python',
              'weekly_purchasing_intelligence.py',
            ),
      );

      final result = await service.analyzeWeeklyPurchasing(
        endDate: DateTime(2026, 9, 30),
        weeks: 2,
      );

      expect(result['schema_version'], 1);
      final totals = result['weekly_totals'] as List<dynamic>;
      expect(totals, hasLength(2));
      expect(totals[0]['week_start'], '2026-09-21');
      expect(totals[0]['total_weight'], 60.0);
      expect(totals[1]['week_start'], '2026-09-28');
      expect(totals[1]['total_weight'], 290.0);

      final latest = result['latest_week'] as Map<String, dynamic>;
      expect(latest['week_over_week_percent'], closeTo(383.3333, 0.001));
      expect(latest['historical_mean'], 60.0);
      expect(latest['historical_median'], 60.0);
      expect(latest['unusual_volume'], isNull);
      expect(
        latest['unusual_volume_explanation'],
        contains('at least 4 prior weeks'),
      );
    },
    skip: testPythonExecutable == null || testPythonExecutable.trim().isEmpty
        ? 'Set WEEKLY_PURCHASING_TEST_PYTHON to run the real Python process test.'
        : false,
  );
}

Future<void> _insertSupplier(
  Database database,
  String internalId,
  String id,
  String name,
  String type,
  String town,
  bool active, {
  required String companyId,
}) async {
  await database.insert('suppliers', {
    'internal_id': internalId,
    'company_id': companyId,
    'supplier_id': id,
    'normalized_name': name.toLowerCase(),
    'name': name,
    'type': type,
    'town': town,
    'district': 'District',
    'region': 'Region',
    'is_active': active ? 1 : 0,
    'created_at': '2026-01-01T00:00:00',
    'updated_at': '2026-01-01T00:00:00',
    'synchronization_status': 'synced',
  });
}

Future<void> _insertDelivery(
  Database database,
  String id,
  String supplierId,
  String productId,
  String productName,
  String supplierType,
  String recordedAt,
  List<double> weights, {
  String status = 'received',
  required String companyId,
}) async {
  await database.insert('deliveries', {
    'id': id,
    'company_id': companyId,
    'supplier_id': supplierId,
    'product_id': productId,
    'recorded_at': recordedAt,
    'recorded_by_user_id': 'user',
    'status': status,
    'synchronization_status': 'synced',
    'supplier_name': supplierId,
    'product_name': productName,
    'supplier_type': supplierType,
    'record_type': 'individual',
    'total_weight': null,
    'bag_count': null,
    'created_at': recordedAt,
    'updated_at': recordedAt,
  });

  for (var index = 0; index < weights.length; index++) {
    await database.insert('delivery_bag_weights', {
      'delivery_id': id,
      'company_id': companyId,
      'bag_number': index + 1,
      'weight': weights[index],
    });
  }
}
