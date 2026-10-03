import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class ProductDatabase {
  static Future<Database> open({String? databasePath}) async {
    final factory = _databaseFactory();
    final directory = await factory.getDatabasesPath();
    return factory.openDatabase(
      databasePath ?? path.join(directory, 'albnc_ventures.db'),
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE products (
              id TEXT NOT NULL,
              company_id TEXT,
              name TEXT NOT NULL COLLATE NOCASE,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (company_id, id),
              UNIQUE (company_id, name)
            )
          ''');
          await _createDeliveryTables(database);
          await _createUserTable(database);
          await _createImportLogTable(database);
          await _createReceiptSendTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createDeliveryTables(database);
          if (oldVersion < 3) await _addDeliveryDisplaySnapshots(database);
          if (oldVersion < 4) await _addSupplierTypeSnapshot(database);
          if (oldVersion < 5) await _createUserTable(database);
          if (oldVersion < 6) await _createImportLogTable(database);
          if (oldVersion < 7) await _addSynchronizationMetadata(database);
          if (oldVersion < 8) await _addSupplierTables(database);
          if (oldVersion < 9) await _addAnalyticsIndexes(database);
          if (oldVersion < 10) await _createUserTable(database);
          if (oldVersion < 11) await _createReceiptSendTable(database);
          if (oldVersion < 12) await _addCompanyIsolation(database);
          if (oldVersion < 13) await _addRecorderIdentity(database);
        },
      ),
    );
  }

  static Future<void> _createDeliveryTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS deliveries (
        id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        recorded_by_user_id TEXT,
        company_id TEXT,
        status TEXT NOT NULL,
        synchronization_status TEXT NOT NULL,
        supplier_internal_id TEXT,
        supplier_name TEXT NOT NULL,
        product_name TEXT NOT NULL,
        supplier_type TEXT NOT NULL,
        synchronization_error TEXT,
        sync_attempts INTEGER NOT NULL DEFAULT 0,
        last_sync_attempt_at TEXT,
        synced_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS delivery_bag_weights (
        delivery_id TEXT NOT NULL,
        company_id TEXT,
        bag_number INTEGER NOT NULL,
        weight REAL NOT NULL,
        recorded_by_user_id TEXT,
        PRIMARY KEY (delivery_id, bag_number),
        FOREIGN KEY (delivery_id) REFERENCES deliveries (id) ON DELETE CASCADE
      )
    ''');
    await _createSupplierTables(database);
  }

  static Future<void> _addDeliveryDisplaySnapshots(Database database) async {
    await _addColumnIfMissing(
      database,
      'deliveries',
      'supplier_name TEXT NOT NULL DEFAULT ""',
    );
    await _addColumnIfMissing(
      database,
      'deliveries',
      'product_name TEXT NOT NULL DEFAULT ""',
    );
  }

  static Future<void> _addSupplierTypeSnapshot(Database database) async {
    await _addColumnIfMissing(
      database,
      'deliveries',
      'supplier_type TEXT NOT NULL DEFAULT "farmer"',
    );
  }

  static Future<void> _createUserTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createImportLogTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_logs (
        id TEXT PRIMARY KEY,
        filename TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        imported_by_user_id TEXT NOT NULL,
        company_id TEXT,
        rows_total INTEGER NOT NULL,
        rows_imported INTEGER NOT NULL,
        rows_skipped INTEGER NOT NULL,
        rows_failed INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createReceiptSendTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS receipt_sends (
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
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_sends_delivery_id ON receipt_sends(delivery_id)',
    );
  }

  static Future<void> _addSynchronizationMetadata(Database database) async {
    await _addColumnIfMissing(
      database,
      'deliveries',
      'synchronization_error TEXT',
    );
    await _addColumnIfMissing(
      database,
      'deliveries',
      'sync_attempts INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      database,
      'deliveries',
      'last_sync_attempt_at TEXT',
    );
    await _addColumnIfMissing(database, 'deliveries', 'synced_at TEXT');
  }

  static Future<void> _addSupplierTables(Database database) async {
    await _createSupplierTables(database);
    await _addColumnIfMissing(
      database,
      'deliveries',
      'supplier_internal_id TEXT',
    );
  }

  static Future<void> _addAnalyticsIndexes(Database database) async {
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_recorded_at ON deliveries(recorded_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_supplier_id ON deliveries(supplier_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_product_id ON deliveries(product_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_supplier_type ON deliveries(supplier_type)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_delivery_bag_weights_delivery_id ON delivery_bag_weights(delivery_id)',
    );
  }

  static Future<void> _createSupplierTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
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
        synchronization_error TEXT,
        UNIQUE (company_id, supplier_id),
        UNIQUE (company_id, normalized_name)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_normalized_name ON suppliers(normalized_name)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_supplier_id ON suppliers(supplier_id)',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _addCompanyIsolation(Database database) async {
    // Some older device databases skipped this table. Recreate its empty
    // schema before adding the tenant column so v11 -> v12 remains safe.
    await _createImportLogTable(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    final productColumns = await database.rawQuery(
      'PRAGMA table_info(products)',
    );
    final hasProductCompany = productColumns.any(
      (column) => column['name'] == 'company_id',
    );
    if (!hasProductCompany) {
      await database.execute(
        'ALTER TABLE products RENAME TO products_before_company',
      );
      await database.execute('''
        CREATE TABLE products (
          id TEXT NOT NULL,
          company_id TEXT,
          name TEXT NOT NULL COLLATE NOCASE,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (company_id, id),
          UNIQUE (company_id, name)
        )
      ''');
      await database.execute('''
        INSERT INTO products(id, company_id, name, is_active, created_at, updated_at)
        SELECT id, NULL, name, is_active, created_at, updated_at FROM products_before_company
      ''');
      await database.execute('DROP TABLE products_before_company');
    }
    await _addColumnIfMissing(database, 'deliveries', 'company_id TEXT');
    await _addColumnIfMissing(
      database,
      'delivery_bag_weights',
      'company_id TEXT',
    );
    await _addColumnIfMissing(database, 'suppliers', 'company_id TEXT');
    await _addColumnIfMissing(database, 'import_logs', 'company_id TEXT');
    await _addColumnIfMissing(database, 'receipt_sends', 'company_id TEXT');
    final supplierSql =
        (await database.rawQuery(
              "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'suppliers'",
            )).single['sql']
            as String? ??
        '';
    if (!supplierSql.toLowerCase().contains(
      'unique (company_id, supplier_id)',
    )) {
      await database.execute(
        'ALTER TABLE suppliers RENAME TO suppliers_before_company',
      );
      await database.execute('''
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
          synchronization_error TEXT,
          UNIQUE (company_id, supplier_id),
          UNIQUE (company_id, normalized_name)
        )
      ''');
      await database.execute('''
        INSERT INTO suppliers(internal_id, supplier_id, company_id, normalized_name, name, type, phone, town, district, region, notes, is_active, created_at, updated_at, synchronization_status, synchronization_error)
        SELECT internal_id, supplier_id, company_id, normalized_name, name, type, phone, town, district, region, notes, is_active, created_at, updated_at, synchronization_status, synchronization_error
        FROM suppliers_before_company
      ''');
      await database.execute('DROP TABLE suppliers_before_company');
    }
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_normalized_name ON suppliers(normalized_name)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_supplier_id ON suppliers(supplier_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_company_recorded_at ON deliveries(company_id, recorded_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_company_supplier_id ON suppliers(company_id, supplier_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_company_name ON products(company_id, name)',
    );
  }

  static Future<void> _addRecorderIdentity(Database database) async {
    final deliveryColumns = await database.rawQuery(
      'PRAGMA table_info(deliveries)',
    );
    final recorderColumn = deliveryColumns.firstWhere(
      (column) => column['name'] == 'recorded_by_user_id',
    );
    if (recorderColumn['notnull'] == 1) {
      // SQLite cannot portably drop NOT NULL. Rebuild the related tables and
      // copy all records without assigning identities to legacy rows.
      await database.execute('''
        CREATE TABLE deliveries_before_recorder_migration AS
        SELECT * FROM deliveries
      ''');
      await database.execute('''
        CREATE TABLE bag_weights_before_recorder_migration AS
        SELECT * FROM delivery_bag_weights
      ''');
      await database.execute('DROP TABLE delivery_bag_weights');
      await database.execute('DROP TABLE deliveries');
      await database.execute('''
        CREATE TABLE deliveries (
          id TEXT PRIMARY KEY,
          supplier_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          recorded_at TEXT NOT NULL,
          recorded_by_user_id TEXT,
          company_id TEXT,
          status TEXT NOT NULL,
          synchronization_status TEXT NOT NULL,
          supplier_internal_id TEXT,
          supplier_name TEXT NOT NULL,
          product_name TEXT NOT NULL,
          supplier_type TEXT NOT NULL,
          synchronization_error TEXT,
          sync_attempts INTEGER NOT NULL DEFAULT 0,
          last_sync_attempt_at TEXT,
          synced_at TEXT,
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
          PRIMARY KEY (delivery_id, bag_number),
          FOREIGN KEY (delivery_id) REFERENCES deliveries (id) ON DELETE CASCADE
        )
      ''');
      await database.execute('''
        INSERT INTO deliveries (
          id, supplier_id, product_id, recorded_at, recorded_by_user_id,
          company_id, status, synchronization_status, supplier_internal_id,
          supplier_name, product_name, supplier_type, synchronization_error,
          sync_attempts, last_sync_attempt_at, synced_at, created_at, updated_at
        )
        SELECT
          id, supplier_id, product_id, recorded_at, recorded_by_user_id,
          company_id, status, synchronization_status, supplier_internal_id,
          supplier_name, product_name, supplier_type, synchronization_error,
          sync_attempts, last_sync_attempt_at, synced_at, created_at, updated_at
        FROM deliveries_before_recorder_migration
      ''');
      await database.execute('''
        INSERT INTO delivery_bag_weights (
          delivery_id, company_id, bag_number, weight, recorded_by_user_id
        )
        SELECT delivery_id, company_id, bag_number, weight, NULL
        FROM bag_weights_before_recorder_migration
      ''');
      await database.execute(
        'DROP TABLE bag_weights_before_recorder_migration',
      );
      await database.execute('DROP TABLE deliveries_before_recorder_migration');
      await _addAnalyticsIndexes(database);
      await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_deliveries_company_recorded_at ON deliveries(company_id, recorded_at)',
      );
    } else {
      await _addColumnIfMissing(
        database,
        'delivery_bag_weights',
        'recorded_by_user_id TEXT',
      );
    }
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_company_recorded_by ON deliveries(company_id, recorded_by_user_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_bag_weights_company_recorded_by ON delivery_bag_weights(company_id, recorded_by_user_id)',
    );
  }

  static Future<void> _addColumnIfMissing(
    Database database,
    String table,
    String definition,
  ) async {
    final columnName = definition.split(' ').first;
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((column) => column['name'] == columnName)) return;
    await database.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  static DatabaseFactory _databaseFactory() {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }
}
