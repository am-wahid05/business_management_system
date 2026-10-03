import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class ProductDatabase {
  static Future<Database> open({
    String? databasePath,
    DatabaseFactory? databaseFactoryOverride,
  }) async {
    final factory = databaseFactoryOverride ?? _databaseFactory();
    final directory = databasePath == null
        ? await factory.getDatabasesPath()
        : null;
    return factory.openDatabase(
      databasePath ?? path.join(directory!, 'albnc_ventures.db'),
      options: OpenDatabaseOptions(
        version: 20,
        onCreate: (database, version) async {
          await _createProductsTable(database);
          await _createDeliveryTables(database);
          await _createUserTable(database);
          await _createReceiptSendTable(database);
          await _createImportLogTable(database);
          await _createSpreadsheetTables(database);
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
          if (oldVersion < 12) await _addSupplierCompanyId(database);
          if (oldVersion < 16) await _scopeSupplierKeysToCompany(database);
          if (oldVersion < 17) await _createSpreadsheetTables(database);
          if (oldVersion < 18) await _addBulkDeliveryColumns(database);
          if (oldVersion < 19) await _addCompanyColumns(database);
          if (oldVersion < 20) await _scopeProductKeysToCompany(database);
        },
      ),
    );
  }

  /// Creates the company-scoped products table.
  ///
  /// `company_id` is part of the table definition from the very first install so
  /// a new database has the same shape an upgraded one does. Every product query
  /// in [ProductRepository] is already written against this column, so creating
  /// the table without it makes startup fail with "no such column: company_id".
  ///
  /// The keys are scoped to the company, exactly like the supplier keys: two
  /// companies each own a copy of Cashew, Shea Nuts and Cocoa, so neither `id`
  /// nor `name` can stay globally unique.
  ///
  /// `company_id` is `TEXT NOT NULL DEFAULT ''`, where `''` marks a row that is
  /// not assigned to a company yet. The pre-scoping database has no company for
  /// its rows, and [ProductRepository] deliberately omits the column on insert
  /// when it runs without a company scope (a local, single-company install has
  /// no tenant id), so the rows must be storable without one. A real value
  /// instead of NULL keeps the composite `PRIMARY KEY (company_id, id)` and
  /// `UNIQUE (company_id, name)` truly unique per tenant — SQLite lets NULLs
  /// slip through composite keys, so NULL would silently allow duplicates.
  /// [ProductRepository._fromRow] maps `''` back to null, so [Product.companyId]
  /// keeps its existing nullable meaning.
  static Future<void> _createProductsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT NOT NULL,
        company_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL COLLATE NOCASE,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (company_id, id),
        UNIQUE (company_id, name)
      )
    ''');
  }

  static Future<void> _createDeliveryTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS deliveries (
        id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        recorded_by_user_id TEXT NOT NULL,
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
        record_type TEXT NOT NULL DEFAULT 'individual',
        total_weight REAL,
        bag_count INTEGER,
        notes TEXT,
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

  /// Adds the local, company-scoped presentation state used by the existing
  /// spreadsheet. This is additive: it does not alter or remove business data.
  static Future<void> _createSpreadsheetTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS spreadsheet_cells (
        company_id TEXT NOT NULL,
        row_key TEXT NOT NULL,
        column_index INTEGER NOT NULL,
        background TEXT NOT NULL DEFAULT 'none',
        text_color TEXT,
        is_bold INTEGER NOT NULL DEFAULT 0,
        is_italic INTEGER NOT NULL DEFAULT 0,
        alignment TEXT NOT NULL DEFAULT 'left',
        PRIMARY KEY (company_id, row_key, column_index)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS spreadsheet_formulas (
        company_id TEXT NOT NULL,
        row_key TEXT NOT NULL,
        column_index INTEGER NOT NULL,
        expression TEXT NOT NULL,
        PRIMARY KEY (company_id, row_key, column_index)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS spreadsheet_merges (
        company_id TEXT NOT NULL,
        anchor_row_key TEXT NOT NULL,
        anchor_column INTEGER NOT NULL,
        end_row_key TEXT NOT NULL,
        end_column INTEGER NOT NULL,
        PRIMARY KEY (company_id, anchor_row_key, anchor_column)
      )
    ''');
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

  /// Adds the weighing-bridge columns to the deliveries table.
  ///
  /// Without these a bulk delivery cannot be read back: the record would be
  /// rebuilt as an individual one with no bag weights, which the model
  /// correctly refuses. The columns are additive and default to an ordinary
  /// individual record, so every delivery saved before this migration keeps
  /// loading exactly as it did.
  static Future<void> _addBulkDeliveryColumns(Database database) async {
    await _addColumnIfMissing(
      database,
      'deliveries',
      "record_type TEXT NOT NULL DEFAULT 'individual'",
    );
    await _addColumnIfMissing(database, 'deliveries', 'total_weight REAL');
    await _addColumnIfMissing(database, 'deliveries', 'bag_count INTEGER');
    await _addColumnIfMissing(database, 'deliveries', 'notes TEXT');
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
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_company_name ON suppliers(company_id, normalized_name)',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _addSupplierCompanyId(Database database) async {
    await _addColumnIfMissing(database, 'suppliers', 'company_id TEXT');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_company_name ON suppliers(company_id, normalized_name)',
    );
  }

  /// Ensure the local keys match the remote supplier tenant keys. Older local
  /// schemas used a global supplier_id key. Rows with a null company_id remain
  /// unassigned; startup has no safe way to determine which tenant owns them.
  static Future<void> _scopeSupplierKeysToCompany(Database database) async {
    // A database older than v8 has no suppliers table yet. Creating the scoped
    // table and copying out of `suppliers` would fail with "no such table", so
    // build the already-scoped table instead and let the copy find nothing.
    final existing = await database.rawQuery('PRAGMA table_info(suppliers)');
    if (existing.isEmpty) {
      await _createSupplierTables(database);
      return;
    }

    Future<bool> hasUniqueIndex(List<String> expectedColumns) async {
      final indexes = await database.rawQuery('PRAGMA index_list(suppliers)');
      for (final index in indexes) {
        if (index['unique'] != 1) continue;
        final indexName = (index['name']! as String).replaceAll('"', '""');
        final columns = await database.rawQuery(
          'PRAGMA index_info("$indexName")',
        );
        if (columns
                .map((column) => column['name'] as String)
                .toList()
                .join('\u0000') ==
            expectedColumns.join('\u0000')) {
          return true;
        }
      }
      return false;
    }

    final hasCompanySupplierKey = await hasUniqueIndex([
      'company_id',
      'supplier_id',
    ]);
    final hasCompanyNameKey = await hasUniqueIndex([
      'company_id',
      'normalized_name',
    ]);
    if (hasCompanySupplierKey && hasCompanyNameKey) return;

    await database.execute('''
      CREATE TABLE suppliers_company_scoped (
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
      INSERT INTO suppliers_company_scoped (
        internal_id, supplier_id, company_id, normalized_name, name, type,
        phone, town, district, region, notes, is_active, created_at, updated_at,
        synchronization_status, synchronization_error
      )
      SELECT
        internal_id, supplier_id, company_id, normalized_name, name, type,
        phone, town, district, region, notes, is_active, created_at, updated_at,
        synchronization_status, synchronization_error
      FROM suppliers
    ''');
    await database.execute('DROP TABLE suppliers');
    await database.execute(
      'ALTER TABLE suppliers_company_scoped RENAME TO suppliers',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_normalized_name ON suppliers(normalized_name)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_supplier_id ON suppliers(supplier_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_company_name ON suppliers(company_id, normalized_name)',
    );
  }

  /// Brings the local tables that the multi-company features filter on up to the
  /// company-scoped shape the repositories already expect.
  ///
  /// `products` only ever needed the column added to it up to v19; v20 is the
  /// version that rebuilds it with company-scoped keys (see
  /// [_scopeProductKeysToCompany]). Every table here ends up with the column,
  /// so this stays a no-op on a database that is already correct.
  static Future<void> _addCompanyColumns(Database database) async {
    await _addColumnIfMissing(database, 'products', 'company_id TEXT');
    await _addColumnIfMissing(database, 'deliveries', 'company_id TEXT');
    await _addColumnIfMissing(database, 'delivery_bag_weights', 'company_id TEXT');
    await _addColumnIfMissing(database, 'receipt_sends', 'company_id TEXT');
    await _addColumnIfMissing(database, 'import_logs', 'company_id TEXT');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_deliveries_company_id ON deliveries(company_id)',
    );
  }

  /// Rebuilds `products` with company-scoped keys, mirroring
  /// [_scopeSupplierKeysToCompany] for suppliers.
  ///
  /// Two companies each own a copy of Cashew, Shea Nuts and Cocoa, so the old
  /// global `id` PRIMARY KEY and global `name` UNIQUE both have to go — the
  /// keys become `PRIMARY KEY (company_id, id)` and
  /// `UNIQUE (company_id, name)`. Rebuilding is the only way to change those
  /// constraints in SQLite; `ALTER TABLE ... ADD COLUMN` cannot. The copy
  /// preserves every existing row. A legacy row gets the unassigned marker
  /// `''`, because startup has no safe way to decide which tenant owns it —
  /// exactly the way the local, non-remote database is a single-company
  /// database with no tenant id at all.
  ///
  /// `company_id` is `TEXT NOT NULL DEFAULT ''` rather than nullable: SQLite
  /// lets NULLs slip through composite keys, so NULL would silently allow two
  /// copies of Cashew for the same company. `''` is a real value, so the keys
  /// hold. [ProductRepository._fromRow] maps `''` back to null, so
  /// [Product.companyId] keeps its existing nullable meaning.
  static Future<void> _scopeProductKeysToCompany(Database database) async {
    final columns = await database.rawQuery('PRAGMA table_info(products)');
    if (columns.isEmpty) return;
    final companyColumn = columns
        .where((column) => column['name'] == 'company_id')
        .toList(growable: false);
    if (companyColumn.isNotEmpty &&
        (companyColumn.single['notnull'] as int? ?? 0) == 1) {
      // Already in the company-scoped shape: nothing left to do.
      return;
    }
    // Covers both the pre-company table (no company_id at all) and the v19
    // shape, where `company_id` was only added as a nullable column. The copy
    // normalises both NULL and missing values to the unassigned marker `''`.
    await database.execute('''
      CREATE TABLE products_company_scoped (
        id TEXT NOT NULL,
        company_id TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL COLLATE NOCASE,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (company_id, id),
        UNIQUE (company_id, name)
      )
    ''');
    await database.execute('''
      INSERT INTO products_company_scoped (
        id, company_id, name, is_active, created_at, updated_at
      )
      SELECT
        id, COALESCE(company_id, ''), name, is_active, created_at, updated_at
      FROM products
    ''');
    await database.execute('DROP TABLE products');
    await database.execute(
      'ALTER TABLE products_company_scoped RENAME TO products',
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
