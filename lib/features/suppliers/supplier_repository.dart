import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../receiving/sms_receipt_service.dart';

import 'package:sqflite/sqflite.dart';

class SupplierRepository {
  SupplierRepository({
    DateTime Function()? now,
    this.database,
    this.companyIdProvider,
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Database? database;
  final String? Function()? companyIdProvider;
  String? get _companyId => companyIdProvider?.call();
  final List<Supplier> _suppliers = [];
  final List<Delivery> _deliveries = [];
  final Set<void Function()> _listeners = {};
  String? _cachedCompanyId;

  bool get usesCompanyScope => companyIdProvider != null;
  String? get activeCompanyId => _companyId;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  List<Supplier> get suppliers {
    _synchronizeCacheScope();
    return List.unmodifiable(_suppliers);
  }

  void clearForCompanyChange() {
    _suppliers.clear();
    _deliveries.clear();
    _cachedCompanyId = _companyId;
  }

  Future<void> initialize() async {
    _synchronizeCacheScope();
    final db = database;
    if (db == null) return;
    if (companyIdProvider != null && _companyId == null) {
      _suppliers.clear();
      _deliveries.clear();
      _notifyListeners();
      return;
    }
    final rows = await db.query(
      'suppliers',
      where: companyIdProvider == null ? null : 'company_id = ?',
      whereArgs: companyIdProvider == null ? null : [_companyId],
      orderBy: 'name COLLATE NOCASE',
    );
    _suppliers
      ..clear()
      ..addAll(rows.map(fromRow));
    _cachedCompanyId = _companyId;
    _notifyListeners();
  }

  void cache(Supplier supplier) {
    _requireActiveCompany();
    _synchronizeCacheScope();
    if (companyIdProvider != null && supplier.companyId != _companyId) {
      throw StateError('Supplier belongs to a different company.');
    }
    _cacheSupplier(supplier);
    _notifyListeners();
  }

  void _cacheSupplier(Supplier supplier) {
    final index = _suppliers.indexWhere(
      (item) => item.internalId == supplier.internalId,
    );
    if (index == -1) {
      _suppliers.add(supplier);
    } else {
      _suppliers[index] = supplier;
    }
  }

  void _notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  List<Supplier> search(String query) {
    _synchronizeCacheScope();
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return suppliers;

    return _suppliers
        .where((supplier) {
          return _normalize(supplier.name).contains(normalizedQuery) ||
              _normalize(supplier.id).contains(normalizedQuery) ||
              _normalize(supplier.phone ?? '').contains(normalizedQuery) ||
              _normalize(supplier.town).contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  Supplier? findById(String id) {
    _synchronizeCacheScope();
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier;
    }
    return null;
  }

  Future<Supplier> create({
    required String name,
    required SupplierType type,
    required String phone,
    required String town,
    required String district,
    required String region,
    required String notes,
  }) async {
    _requireActiveCompany();
    _synchronizeCacheScope();
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required');
    // The contact is normalized when one is supplied. A contact is REQUIRED by
    // the admin Create Supplier form, which validates before calling this, but
    // this repository is also used to provision a supplier automatically from a
    // delivery or a spreadsheet row, where the contact may genuinely not be
    // known yet. Rejecting it here would stop those deliveries from being
    // recorded at all, so the rule lives in the form rather than here.
    final contact = _normalizeContact(phone);
    final db = database;
    late final Supplier supplier;
    if (db == null) {
      _validateCachedName(name);
      supplier = _buildSupplier(
        id: await _nextId(),
        name: name,
        type: type,
        phone: contact,
        town: town,
        district: district,
        region: region,
        notes: notes,
      );
    } else {
      supplier = await db.transaction((transaction) async {
        await _ensureNameAvailable(transaction, name);
        final id = await _nextId(transaction);
        final created = _buildSupplier(
          id: id,
          name: name,
          type: type,
          phone: contact,
          town: town,
          district: district,
          region: region,
          notes: notes,
        );
        await transaction.insert('suppliers', toRow(created));
        return created;
      });
    }
    cache(supplier);
    return supplier;
  }

  /// Imports selected supplier names as active farmers in one SQLite
  /// transaction. Name normalization and company scope are the same as normal
  /// creation, so duplicates are counted rather than inserted.
  ///
  /// Empty names are skipped and repeated normalized names in [names] are
  /// counted as workbook duplicates. Existing suppliers are checked again
  /// inside the transaction to cover changes made after a preview was shown.
  Future<SupplierBulkImportResult> importNames(Iterable<String> names) async {
    _synchronizeCacheScope();
    final activeCompanyId = _companyId;
    if (companyIdProvider != null &&
        (activeCompanyId == null || activeCompanyId.trim().isEmpty)) {
      throw StateError('Supplier import requires an active company.');
    }

    final uniqueNames = <String>[];
    final seenNames = <String>{};
    var skipped = 0;
    var duplicates = 0;
    for (final value in names) {
      final name = _cleanName(value);
      if (name.isEmpty) {
        skipped++;
        continue;
      }
      if (!seenNames.add(normalizeName(name))) {
        duplicates++;
        continue;
      }
      uniqueNames.add(name);
    }

    if (uniqueNames.isEmpty) {
      return SupplierBulkImportResult(
        created: const [],
        alreadyExisted: 0,
        skipped: skipped,
        duplicates: duplicates,
      );
    }

    final created = <Supplier>[];
    final reservedIds = <String>{};
    var alreadyExisted = 0;
    final db = database;

    Future<void> insertInto(DatabaseExecutor executor) async {
      for (final name in uniqueNames) {
        if (companyIdProvider != null && _companyId != activeCompanyId) {
          throw StateError(
            'The active company changed during supplier import.',
          );
        }
        final where = <String>[];
        final arguments = <Object?>[];
        if (companyIdProvider != null) {
          where.add('company_id = ?');
          arguments.add(activeCompanyId);
        }
        where.add('normalized_name = ?');
        arguments.add(normalizeName(name));
        final matches = await executor.query(
          'suppliers',
          columns: const ['supplier_id'],
          where: where.join(' AND '),
          whereArgs: arguments,
          limit: 1,
        );
        if (matches.isNotEmpty) {
          alreadyExisted++;
          continue;
        }

        final id = await _nextId(executor, reservedIds);
        reservedIds.add(id);
        final supplier = _buildSupplier(
          id: id,
          name: name,
          type: SupplierType.farmer,
          phone: null,
          town: '',
          district: '',
          region: '',
          notes: '',
          companyId: activeCompanyId,
        );
        await executor.insert('suppliers', toRow(supplier));
        created.add(supplier);
      }
    }

    if (db == null) {
      // The in-memory mode is kept for existing demo/test configurations. The
      // production repository has a database and uses the atomic branch below.
      final existingNames = _suppliers
          .map((supplier) => normalizeName(supplier.name))
          .toSet();
      for (final name in uniqueNames) {
        if (existingNames.contains(normalizeName(name))) {
          alreadyExisted++;
          continue;
        }
        final id = await _nextId(null, reservedIds);
        reservedIds.add(id);
        created.add(
          _buildSupplier(
            id: id,
            name: name,
            type: SupplierType.farmer,
            phone: null,
            town: '',
            district: '',
            region: '',
            notes: '',
            companyId: activeCompanyId,
          ),
        );
        existingNames.add(normalizeName(name));
      }
    } else {
      await db.transaction(insertInto);
    }

    if (companyIdProvider == null || _companyId == activeCompanyId) {
      for (final supplier in created) {
        _cacheSupplier(supplier);
      }
      if (created.isNotEmpty) _notifyListeners();
    }
    return SupplierBulkImportResult(
      created: List.unmodifiable(created),
      alreadyExisted: alreadyExisted,
      skipped: skipped,
      duplicates: duplicates,
    );
  }

  Future<Supplier> update(Supplier updatedSupplier) async {
    _requireActiveCompany();
    _synchronizeCacheScope();
    if (companyIdProvider != null && updatedSupplier.companyId != _companyId) {
      throw StateError('Supplier belongs to a different company.');
    }
    final index = _suppliers.indexWhere(
      (supplier) =>
          supplier.id == updatedSupplier.id &&
          (companyIdProvider == null || supplier.companyId == _companyId),
    );
    final db = database;
    late final Supplier updated;
    if (db == null) {
      if (index == -1) {
        throw StateError('Supplier ${updatedSupplier.id} was not found');
      }
      _validateCachedName(
        updatedSupplier.name,
        excludingId: updatedSupplier.id,
      );
      updated = updatedSupplier.copyWith(
        name: _cleanName(updatedSupplier.name),
        updatedAt: _now(),
      );
    } else {
      updated = await db.transaction((transaction) async {
        final existing = await transaction.query(
          'suppliers',
          where: _supplierIdWhere,
          whereArgs: _supplierIdArgs(updatedSupplier.id),
          limit: 1,
        );
        if (existing.isEmpty) {
          throw StateError('Supplier ${updatedSupplier.id} was not found');
        }
        await _ensureNameAvailable(
          transaction,
          updatedSupplier.name,
          excludingId: updatedSupplier.id,
        );
        final changed = updatedSupplier.copyWith(
          name: _cleanName(updatedSupplier.name),
          updatedAt: _now(),
        );
        final count = await transaction.update(
          'suppliers',
          _editableColumns(changed),
          where: _supplierIdWhere,
          whereArgs: _supplierIdArgs(updatedSupplier.id),
        );
        if (count == 0) {
          throw StateError('Supplier ${updatedSupplier.id} was not found');
        }
        return changed;
      });
    }
    cache(updated);
    return updated;
  }

  Future<Supplier> setActive(String id, bool isActive) async {
    _requireActiveCompany();
    final supplier = findById(id);
    if (supplier == null) throw StateError('Supplier $id was not found');
    return update(supplier.copyWith(isActive: isActive));
  }

  /// Reuses an active supplier in the current company, or creates and inserts
  /// one using the caller's existing ID-generation policy. The caller owns the
  /// surrounding transaction, so supplier and delivery changes can commit as
  /// one unit.
  Future<Supplier> findOrCreateInTransaction(
    DatabaseExecutor transaction, {
    String? supplierId,
    required String name,
    required SupplierType type,
    required String town,
    required String district,
    required String region,
    String? phone,
    String? notes,
    required Future<String> Function() createId,
    String Function()? createInternalId,
  }) async {
    _requireActiveCompany();
    _synchronizeCacheScope();
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required');

    final normalizedName = normalizeName(name);
    final cleanSupplierId = supplierId?.trim();
    final where = <String>[];
    final arguments = <Object?>[];
    if (companyIdProvider != null) {
      where.add('company_id = ?');
      arguments.add(_companyId);
    }
    if (cleanSupplierId == null || cleanSupplierId.isEmpty) {
      where.add('normalized_name = ?');
      arguments.add(normalizedName);
    } else {
      where.add('(supplier_id = ? OR normalized_name = ?)');
      arguments
        ..add(cleanSupplierId)
        ..add(normalizedName);
    }
    where.add('is_active = 1');
    final existing = await transaction.query(
      'suppliers',
      where: where.join(' AND '),
      whereArgs: arguments,
      limit: 1,
    );
    if (existing.isNotEmpty) return fromRow(existing.single);

    final id = await createId();
    final supplier = _buildSupplier(
      id: id,
      internalId: createInternalId?.call() ?? id,
      name: name,
      type: type,
      phone: phone == null ? null : _normalizeContact(phone),
      town: town,
      district: district,
      region: region,
      notes: notes ?? '',
    );
    // Receiving historically creates a new active supplier when only an
    // inactive same-name profile exists. That behavior is retained here.
    await transaction.insert('suppliers', toRow(supplier));
    return supplier;
  }

  void addDelivery(Delivery delivery) {
    _requireActiveCompany();
    if (companyIdProvider != null && delivery.companyId != _companyId) {
      throw StateError('Delivery belongs to a different company.');
    }
    if (findById(delivery.supplier.id) == null) {
      throw StateError('Delivery supplier does not exist in this repository');
    }
    _deliveries.add(delivery);
  }

  List<Delivery> deliveryHistory(
    String supplierId, {
    DateTime? date,
    Product? product,
    int? year,
  }) {
    return _deliveries
        .where((delivery) {
          if (delivery.supplier.id != supplierId) return false;
          if (date != null && !_sameDate(delivery.recordedAt, date)) {
            return false;
          }
          if (product != null && delivery.product.id != product.id) {
            return false;
          }
          if (year != null && delivery.recordedAt.year != year) return false;
          return true;
        })
        .toList(growable: false);
  }

  SupplierTotals totals(
    String supplierId, {
    DateTime? date,
    Product? product,
    int? year,
  }) {
    final history = deliveryHistory(
      supplierId,
      date: date,
      product: product,
      year: year,
    );
    return SupplierTotals(
      deliveryCount: history.length,
      bagCount: history.fold(
        0,
        (total, delivery) => total + delivery.numberOfBags,
      ),
      totalWeight: history.fold(
        0,
        (total, delivery) => total + delivery.totalWeight,
      ),
    );
  }

  Future<String> _nextId([
    DatabaseExecutor? executor,
    Set<String> reservedIds = const {},
  ]) async {
    var number = _suppliers.length + 1;
    while (true) {
      final candidate = 'ALB-${number.toString().padLeft(6, '0')}';
      final inCache = _suppliers.any((supplier) => supplier.id == candidate);
      final rows = executor == null
          ? const <Map<String, Object?>>[]
          : await executor.query(
              'suppliers',
              columns: const ['supplier_id'],
              where: 'supplier_id = ?',
              whereArgs: [candidate],
              limit: 1,
            );
      if (!inCache && !reservedIds.contains(candidate) && rows.isEmpty) {
        return candidate;
      }
      number++;
    }
  }

  String get _supplierIdWhere => companyIdProvider == null
      ? 'supplier_id = ?'
      : 'supplier_id = ? AND company_id = ?';

  List<Object?> _supplierIdArgs(String id) => [
    id,
    if (companyIdProvider != null) _companyId,
  ];

  Future<void> _ensureNameAvailable(
    DatabaseExecutor transaction,
    String name, {
    String? excludingId,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required');
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (companyIdProvider != null) {
      clauses.add('company_id = ?');
      arguments.add(_companyId);
    }
    clauses.add('normalized_name = ?');
    arguments.add(normalizeName(name));
    if (excludingId != null) {
      clauses.add('supplier_id != ?');
      arguments.add(excludingId);
    }
    final duplicates = await transaction.query(
      'suppliers',
      columns: const ['supplier_id'],
      where: clauses.join(' AND '),
      whereArgs: arguments,
      limit: 1,
    );
    if (duplicates.isNotEmpty) {
      throw StateError('A supplier with this name already exists');
    }
  }

  void _validateCachedName(String name, {String? excludingId}) {
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required');
    final duplicate = _suppliers.where((supplier) {
      return supplier.id != excludingId &&
          _normalize(supplier.name) == _normalize(name);
    });
    if (duplicate.isNotEmpty) {
      throw StateError('A supplier with this name already exists');
    }
  }

  Supplier _buildSupplier({
    required String id,
    String? internalId,
    required String name,
    required SupplierType type,
    String? phone,
    required String town,
    required String district,
    required String region,
    required String notes,
    String? companyId,
  }) {
    final now = _now();
    return Supplier(
      internalId: internalId ?? id,
      id: id,
      name: _cleanName(name),
      type: type,
      phone: phone,
      town: town.trim(),
      district: district.trim(),
      region: region.trim(),
      companyId: companyId ?? _companyId,
      notes: _optional(notes),
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _cleanName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static Map<String, Object?> _editableColumns(Supplier supplier) => {
    'normalized_name': normalizeName(supplier.name),
    'name': supplier.name,
    'type': supplier.type.name,
    'phone': supplier.phone,
    'town': supplier.town,
    'district': supplier.district,
    'region': supplier.region,
    'notes': supplier.notes,
    'is_active': supplier.isActive ? 1 : 0,
    'updated_at': supplier.updatedAt.toIso8601String(),
  };

  void _synchronizeCacheScope() {
    if (companyIdProvider == null) return;
    final activeCompanyId = _companyId;
    if (_cachedCompanyId == activeCompanyId) return;
    _suppliers.clear();
    _deliveries.clear();
    _cachedCompanyId = activeCompanyId;
  }

  void _requireActiveCompany() {
    if (companyIdProvider != null && _companyId == null) {
      throw StateError('Select an active company before changing suppliers.');
    }
  }

  /// Normalizes a supplier contact number when one is supplied.
  ///
  /// This reuses the project's existing Ghana phone normalization rather than
  /// inventing a second format system, so a number that the SMS path would
  /// accept is stored in its canonical form.
  ///
  /// A blank contact stays null, and a value that is not a Ghana number is kept
  /// as typed rather than rejected. Rejecting it here would stop deliveries and
  /// spreadsheet rows from being recorded at all, because a supplier can be
  /// provisioned automatically before its number is known. Validity is enforced
  /// by the Create Supplier form, which is where a contact is required.
  static String? _normalizeContact(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return null;
    return GhanaPhoneNumber.normalize(trimmed) ?? trimmed;
  }

  static String normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static Supplier fromRow(Map<String, Object?> row) => Supplier(
    internalId: row['internal_id']! as String,
    id: row['supplier_id']! as String,
    name: row['name']! as String,
    type: SupplierType.values.byName(row['type']! as String),
    phone: row['phone'] as String?,
    town: row['town']! as String,
    district: row['district']! as String,
    region: row['region']! as String,
    companyId: row['company_id'] as String?,
    notes: row['notes'] as String?,
    isActive: row['is_active'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  static Map<String, Object?> toRow(Supplier supplier) => {
    'internal_id': supplier.internalId,
    'supplier_id': supplier.id,
    if (supplier.companyId != null) 'company_id': supplier.companyId,
    'normalized_name': normalizeName(supplier.name),
    'name': supplier.name,
    'type': supplier.type.name,
    'phone': supplier.phone,
    'town': supplier.town,
    'district': supplier.district,
    'region': supplier.region,
    'notes': supplier.notes,
    'is_active': supplier.isActive ? 1 : 0,
    'created_at': supplier.createdAt.toIso8601String(),
    'updated_at': supplier.updatedAt.toIso8601String(),
    'synchronization_status': 'pendingSync',
  };

  static String _normalize(String value) => normalizeName(value);

  static String? _optional(String value) =>
      value.trim().isEmpty ? null : value.trim();

  static bool _sameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class SupplierTotals {
  const SupplierTotals({
    required this.deliveryCount,
    required this.bagCount,
    required this.totalWeight,
  });

  final int deliveryCount;
  final int bagCount;
  final double totalWeight;
}

class SupplierBulkImportResult {
  const SupplierBulkImportResult({
    required this.created,
    required this.alreadyExisted,
    required this.skipped,
    required this.duplicates,
  });

  final List<Supplier> created;
  final int alreadyExisted;
  final int skipped;
  final int duplicates;

  int get createdCount => created.length;
}
