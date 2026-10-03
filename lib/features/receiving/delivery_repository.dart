import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../suppliers/supplier_repository.dart';

class DeliveryRepository {
  DeliveryRepository(
    this.database, {
    this.companyIdProvider,
    this.userIdProvider,
  });

  final Database database;
  final String? Function()? companyIdProvider;
  final String? Function()? userIdProvider;
  String? get _companyId => companyIdProvider?.call();
  bool get _usesCompanyScope => companyIdProvider != null;

  Future<void> save(Delivery delivery) async {
    _requireActiveCompany(delivery);
    if (await findById(delivery.id) != null) {
      throw DuplicateDeliveryException(delivery.id);
    }
    final createdAt = DateTime.now().toIso8601String();
    await database.transaction((transaction) async {
      await saveInTransaction(transaction, delivery, createdAt: createdAt);
    });
  }

  Future<void> saveInTransaction(
    DatabaseExecutor transaction,
    Delivery delivery, {
    String? createdAt,
  }) async {
    _requireActiveCompany(delivery);
    final columns = await transaction.rawQuery('PRAGMA table_info(deliveries)');
    final weightColumns = await transaction.rawQuery(
      'PRAGMA table_info(delivery_bag_weights)',
    );
    final actorId = userIdProvider?.call();
    if (userIdProvider != null && actorId == null) {
      throw StateError('Sign in before recording a delivery.');
    }
    if (actorId != null &&
        delivery.recordedByUserId != null &&
        delivery.recordedByUserId != actorId) {
      throw StateError('A delivery must be recorded by the signed-in user.');
    }
    if (actorId != null &&
        delivery.bagRecordedByUserIds.any(
          (recordedBy) => recordedBy != null && recordedBy != actorId,
        )) {
      throw StateError('Bag weights must be recorded by the signed-in user.');
    }
    final recordedByUserId = actorId ?? delivery.recordedByUserId;
    final hasSupplierInternalId = columns.any(
      (column) => column['name'] == 'supplier_internal_id',
    );
    final columnNames = columns
        .map((column) => column['name'] as String)
        .toSet();
    final row = <String, Object?>{
      'id': delivery.id,
      'supplier_id': delivery.supplier.id,
      'product_id': delivery.product.id,
      'recorded_at': delivery.recordedAt.toIso8601String(),
      'recorded_by_user_id': recordedByUserId,
      'status': delivery.status.name,
      'synchronization_status': delivery.synchronizationStatus.name,
      'supplier_name': delivery.supplier.name,
      'product_name': delivery.product.name,
      'supplier_type': delivery.supplier.type.name,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'updated_at': delivery.updatedAt.toIso8601String(),
    };
    if (hasSupplierInternalId) {
      row['supplier_internal_id'] = delivery.supplier.internalId;
    }
    if (columns.any((column) => column['name'] == 'company_id')) {
      row['company_id'] = _usesCompanyScope ? _companyId : delivery.companyId;
    }
    // Bulk / weighing-bridge fields, written only when the column exists so an
    // older local database keeps working unchanged.
    if (columnNames.contains('record_type')) {
      row['record_type'] = delivery.recordType.name;
    }
    if (columnNames.contains('total_weight')) {
      // For an individual record this mirrors the derived bag-weight sum, so
      // reporting can read one column. A bulk record stores its own total.
      row['total_weight'] = delivery.totalWeight;
    }
    if (columnNames.contains('bag_count')) {
      row['bag_count'] = delivery.numberOfBags;
    }
    if (columnNames.contains('notes')) {
      row['notes'] = delivery.notes;
    }
    await transaction.insert('deliveries', row);

    final hasWeightRecorder = weightColumns.any(
      (column) => column['name'] == 'recorded_by_user_id',
    );
    for (var index = 0; index < delivery.bagWeights.length; index++) {
      final weightRecorder =
          actorId ??
          (delivery.bagRecordedByUserIds.isEmpty
              ? recordedByUserId
              : delivery.bagRecordedByUserIds[index]);
      await transaction.insert('delivery_bag_weights', {
        'delivery_id': delivery.id,
        if (columns.any((column) => column['name'] == 'company_id'))
          'company_id': _usesCompanyScope ? _companyId : delivery.companyId,
        'bag_number': index + 1,
        'weight': delivery.bagWeights[index],
        if (hasWeightRecorder) 'recorded_by_user_id': weightRecorder,
      });
    }
  }

  Future<int> count() async {
    if (_usesCompanyScope && _companyId == null) return 0;
    final result = await database.rawQuery(
      _usesCompanyScope
          ? 'SELECT COUNT(*) AS count FROM deliveries WHERE company_id IS ?'
          : 'SELECT COUNT(*) AS count FROM deliveries',
      _usesCompanyScope ? [_companyId] : null,
    );
    return result.single['count']! as int;
  }

  Future<List<Delivery>> unsynchronized() async {
    if (_usesCompanyScope && _companyId == null) return const [];
    final rows = await database.query(
      'deliveries',
      where: _usesCompanyScope
          ? 'company_id IS ? AND synchronization_status IN (?, ?, ?, ?)'
          : 'synchronization_status IN (?, ?, ?, ?)',
      whereArgs: _usesCompanyScope
          ? [_companyId, 'localOnly', 'pendingSync', 'pending', 'syncFailed']
          : ['localOnly', 'pendingSync', 'pending', 'syncFailed'],
      orderBy: 'recorded_at ASC',
    );
    return _loadDeliveries(rows);
  }

  Future<void> recordSyncAttempt(String id, DateTime attemptedAt) async {
    if (_usesCompanyScope && _companyId == null) return;
    await database.rawUpdate(
      'UPDATE deliveries SET synchronization_status = ?, sync_attempts = sync_attempts + 1, last_sync_attempt_at = ? WHERE id = ?${_usesCompanyScope ? ' AND company_id IS ?' : ''}',
      [
        'pendingSync',
        attemptedAt.toIso8601String(),
        id,
        if (_usesCompanyScope) _companyId,
      ],
    );
  }

  Future<void> markSynced(String id, DateTime syncedAt) async {
    if (_usesCompanyScope && _companyId == null) return;
    await database.update(
      'deliveries',
      {
        'synchronization_status': 'synced',
        'synchronization_error': null,
        'synced_at': syncedAt.toIso8601String(),
      },
      where: _usesCompanyScope ? 'id = ? AND company_id IS ?' : 'id = ?',
      whereArgs: _usesCompanyScope ? [id, _companyId] : [id],
    );
  }

  Future<void> markSyncFailed(
    String id,
    String error,
    DateTime attemptedAt,
  ) async {
    if (_usesCompanyScope && _companyId == null) return;
    await database.update(
      'deliveries',
      {
        'synchronization_status': 'syncFailed',
        'synchronization_error': error,
        'last_sync_attempt_at': attemptedAt.toIso8601String(),
      },
      where: _usesCompanyScope ? 'id = ? AND company_id IS ?' : 'id = ?',
      whereArgs: _usesCompanyScope ? [id, _companyId] : [id],
    );
  }

  Future<List<Delivery>> forDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return forRange(start, end);
  }

  Future<List<Delivery>> forRange(
    DateTime start,
    DateTime end, {
    String? supplierId,
    String? productId,
  }) async {
    if (_usesCompanyScope && _companyId == null) return const [];
    final clauses = <String>['recorded_at >= ?', 'recorded_at < ?'];
    final arguments = <Object?>[start.toIso8601String(), end.toIso8601String()];
    if (_usesCompanyScope) {
      clauses.add('company_id IS ?');
      arguments.add(_companyId);
    }
    if (supplierId != null) {
      clauses.add('supplier_id = ?');
      arguments.add(supplierId);
    }
    if (productId != null) {
      clauses.add('product_id = ?');
      arguments.add(productId);
    }
    final rows = await database.query(
      'deliveries',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'recorded_at DESC',
    );
    return _loadDeliveries(rows);
  }

  /// Every delivery recorded for one supplier in the active company.
  ///
  /// This is the authoritative company-scoped history used by the supplier
  /// profile, so the profile and the supplier statement are guaranteed to be
  /// built from exactly the same rows. The `company_id` clause is mandatory
  /// whenever a company scope exists, which is what stops one company's
  /// history from ever being visible to another.
  ///
  /// [from] and [to] are optional; when supplied, [to] is exclusive.
  Future<List<Delivery>> forSupplier(
    String supplierId, {
    DateTime? from,
    DateTime? to,
  }) async {
    if (_usesCompanyScope && _companyId == null) return const [];
    final clauses = <String>['supplier_id = ?'];
    final arguments = <Object?>[supplierId];
    if (_usesCompanyScope) {
      clauses.add('company_id IS ?');
      arguments.add(_companyId);
    }
    if (from != null) {
      clauses.add('recorded_at >= ?');
      arguments.add(from.toIso8601String());
    }
    if (to != null) {
      clauses.add('recorded_at < ?');
      arguments.add(to.toIso8601String());
    }
    final rows = await database.query(
      'deliveries',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'recorded_at DESC',
    );
    return _loadDeliveries(rows);
  }

  Future<Delivery?> findById(String id) async {
    if (_usesCompanyScope && _companyId == null) return null;
    final rows = await database.query(
      'deliveries',
      where: _usesCompanyScope ? 'id = ? AND company_id IS ?' : 'id = ?',
      whereArgs: _usesCompanyScope ? [id, _companyId] : [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _loadDeliveries(rows)).single;
  }

  Future<bool> hasLikelyDuplicate({
    required DateTime recordedAt,
    required String supplierId,
    String? supplierName,
    required String productId,
    required double totalWeight,
  }) async {
    if (_usesCompanyScope && _companyId == null) return false;
    final start = DateTime(recordedAt.year, recordedAt.month, recordedAt.day);
    final end = start.add(const Duration(days: 1));
    final rows = await database.query(
      'deliveries',
      columns: ['id'],
      where:
          'recorded_at >= ? AND recorded_at < ? AND product_id = ?${_usesCompanyScope ? ' AND company_id IS ?' : ''}',
      whereArgs: [
        start.toIso8601String(),
        end.toIso8601String(),
        productId,
        if (_usesCompanyScope) _companyId,
      ],
    );
    for (final row in rows) {
      final delivery = await findById(row['id']! as String);
      final sameSupplier =
          delivery != null &&
          (delivery.supplier.id == supplierId ||
              (supplierName != null &&
                  SupplierRepository.normalizeName(delivery.supplier.name) ==
                      SupplierRepository.normalizeName(supplierName)));
      if (sameSupplier && (delivery.totalWeight - totalWeight).abs() < 0.01) {
        return true;
      }
    }
    return false;
  }

  Future<Delivery> updateWeights(String id, List<double> weights) async {
    if (_usesCompanyScope && _companyId == null) {
      throw StateError(
        'Select an active company before changing delivery weights.',
      );
    }
    final existing = await findById(id);
    if (existing == null) throw StateError('Delivery $id was not found');
    if (existing.isBulk) {
      // A weighing-bridge record must never be turned into bag weights. The
      // spreadsheet cannot convert a bulk record into an individual one.
      throw StateError(
        'This is a bulk weighing-bridge record and has no individual bag '
        'weights. Edit the total weight and bag count instead.',
      );
    }
    final corrected = Delivery(
      id: existing.id,
      supplier: existing.supplier,
      product: existing.product,
      recordedAt: existing.recordedAt,
      bagWeights: weights,
      recordedByUserId: existing.recordedByUserId,
      bagRecordedByUserIds: List.generate(
        weights.length,
        (index) => index < existing.bagRecordedByUserIds.length
            ? existing.bagRecordedByUserIds[index]
            : userIdProvider?.call(),
      ),
      companyId: existing.companyId,
      status: DeliveryStatus.corrected,
      synchronizationStatus: SynchronizationStatus.pending,
      updatedAt: DateTime.now(),
    );
    await database.transaction((transaction) async {
      await transaction.update(
        'deliveries',
        {
          'status': corrected.status.name,
          'synchronization_status': corrected.synchronizationStatus.name,
          'updated_at': corrected.updatedAt.toIso8601String(),
        },
        where: _usesCompanyScope ? 'id = ? AND company_id IS ?' : 'id = ?',
        whereArgs: _usesCompanyScope ? [id, _companyId] : [id],
      );
      final weightColumns = await transaction.rawQuery(
        'PRAGMA table_info(delivery_bag_weights)',
      );
      final hasWeightRecorder = weightColumns.any(
        (column) => column['name'] == 'recorded_by_user_id',
      );
      final existingWeights = await transaction.query(
        'delivery_bag_weights',
        where: _usesCompanyScope
            ? 'delivery_id = ? AND company_id IS ?'
            : 'delivery_id = ?',
        whereArgs: _usesCompanyScope ? [id, _companyId] : [id],
        orderBy: 'bag_number',
      );
      final oldByNumber = {
        for (final row in existingWeights) row['bag_number']! as int: row,
      };
      await transaction.delete(
        'delivery_bag_weights',
        where: _usesCompanyScope
            ? 'delivery_id = ? AND company_id IS ? AND bag_number > ?'
            : 'delivery_id = ? AND bag_number > ?',
        whereArgs: _usesCompanyScope
            ? [id, _companyId, corrected.bagWeights.length]
            : [id, corrected.bagWeights.length],
      );
      for (var index = 0; index < corrected.bagWeights.length; index++) {
        final bagNumber = index + 1;
        final existingWeight = oldByNumber[bagNumber];
        if (existingWeight != null) {
          await transaction.update(
            'delivery_bag_weights',
            {'weight': corrected.bagWeights[index]},
            where: _usesCompanyScope
                ? 'delivery_id = ? AND company_id IS ? AND bag_number = ?'
                : 'delivery_id = ? AND bag_number = ?',
            whereArgs: _usesCompanyScope
                ? [id, _companyId, bagNumber]
                : [id, bagNumber],
          );
        } else {
          await transaction.insert('delivery_bag_weights', {
            'delivery_id': id,
            if (_usesCompanyScope) 'company_id': _companyId,
            'bag_number': bagNumber,
            'weight': corrected.bagWeights[index],
            if (hasWeightRecorder)
              'recorded_by_user_id': corrected.bagRecordedByUserIds[index],
          });
        }
      }
    });
    return corrected;
  }

  /// Updates a bulk / weighing-bridge record's own fields.
  ///
  /// Only the fields that exist for a bulk record are writable: the total
  /// weight, the bag count and the notes. The record stays bulk, keeps its
  /// original recorder, is marked corrected and is queued for sync. There are
  /// deliberately no bag weight writes here, so a bulk record can never gain
  /// invented bags.
  Future<Delivery> updateBulkTotals(
    String id, {
    required double totalWeight,
    required int bagCount,
    String? notes,
  }) async {
    if (_usesCompanyScope && _companyId == null) {
      throw StateError(
        'Select an active company before changing a bulk record.',
      );
    }
    final existing = await findById(id);
    if (existing == null) throw StateError('Delivery $id was not found');
    if (!existing.isBulk) {
      throw StateError(
        'This is an individual record. Change its bag weights instead.',
      );
    }
    if (!totalWeight.isFinite || totalWeight <= 0) {
      throw StateError('Total weight must be greater than zero.');
    }
    if (bagCount <= 0) {
      throw StateError('Number of bags must be greater than zero.');
    }
    final corrected = existing.copyWith(
      bulkTotalWeight: totalWeight,
      bulkBagCount: bagCount,
      notes: notes,
      status: DeliveryStatus.corrected,
      synchronizationStatus: SynchronizationStatus.pending,
      updatedAt: DateTime.now(),
    );
    await database.update(
      'deliveries',
      {
        'total_weight': totalWeight,
        'bag_count': bagCount,
        'notes': corrected.notes,
        'status': corrected.status.name,
        'synchronization_status': corrected.synchronizationStatus.name,
        'updated_at': corrected.updatedAt.toIso8601String(),
      },
      where: _usesCompanyScope ? 'id = ? AND company_id IS ?' : 'id = ?',
      whereArgs: _usesCompanyScope ? [id, _companyId] : [id],
    );
    return corrected;
  }

  /// Searches saved receipts. The existing delivery record is the source of
  /// truth: this only reads, and never creates or modifies a receipt, so
  /// searching, printing or sending an SMS can never duplicate a receipt.
  ///
  /// Every clause is combined with the company scope, so a user can only ever
  /// search receipts belonging to their own company.
  Future<List<Delivery>> search(ReceiptSearchFilters filters) async {
    if (_usesCompanyScope && _companyId == null) return const [];
    final clauses = <String>[];
    final arguments = <Object?>[];

    if (_usesCompanyScope) {
      clauses.add('company_id IS ?');
      arguments.add(_companyId);
    }
    final from = filters.from;
    if (from != null) {
      clauses.add('recorded_at >= ?');
      arguments.add(from.toIso8601String());
    }
    final to = filters.to;
    if (to != null) {
      clauses.add('recorded_at < ?');
      arguments.add(to.toIso8601String());
    }
    final recorder = filters.recorderUserId;
    if (recorder != null && recorder.isNotEmpty) {
      clauses.add('recorded_by_user_id = ?');
      arguments.add(recorder);
    }
    final term = filters.query?.trim() ?? '';
    if (term.isNotEmpty) {
      // Matches the receipt identifier or the supplier/customer name.
      final like = '%${term.toLowerCase()}%';
      clauses.add(
        '(LOWER(id) LIKE ? OR LOWER(supplier_name) LIKE ? OR LOWER(supplier_id) LIKE ?)',
      );
      arguments.addAll([like, like, like]);
    }
    final phone = filters.phone?.trim() ?? '';
    if (phone.isNotEmpty) {
      final supplierIds = await _supplierIdsMatchingPhone(phone);
      if (supplierIds.isEmpty) return const [];
      final placeholders = List.filled(supplierIds.length, '?').join(', ');
      clauses.add('supplier_id IN ($placeholders)');
      arguments.addAll(supplierIds);
    }
    if (clauses.isEmpty) clauses.add('1 = 1');
    final rows = await database.query(
      'deliveries',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'recorded_at DESC',
      limit: filters.limit,
    );
    return _loadDeliveries(rows);
  }

  /// Supplier business IDs whose saved phone contains the last digits of
  /// [phone]. Scoped to the active company so a search cannot reach another
  /// company's supplier list.
  Future<List<String>> _supplierIdsMatchingPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const [];
    final tail = digits.length > 4
        ? digits.substring(digits.length - 4)
        : digits;
    final rows = await database.query(
      'suppliers',
      columns: ['supplier_id'],
      where:
          'phone IS NOT NULL AND LOWER(REPLACE(REPLACE(REPLACE(phone, \' \', \'\'), \'-\', \'\'), \'+\', \'\')) LIKE ?${_usesCompanyScope ? ' AND company_id IS ?' : ''}',
      whereArgs: _usesCompanyScope ? ['%$tail%', _companyId] : ['%$tail%'],
      limit: 500,
    );
    return rows
        .map((row) => row['supplier_id']! as String)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// The most recent SMS attempt for each of [deliveryIds], keyed by delivery
  /// id. Scoped to the active company.
  ///
  /// A provider 202 is stored as `queued` and is reported as queued, never as
  /// delivered. Absent entries mean the receipt was never sent by SMS.
  Future<Map<String, ReceiptSmsRecord>> receiptSmsFor(
    List<String> deliveryIds,
  ) async {
    if (deliveryIds.isEmpty) return const {};
    if (_usesCompanyScope && _companyId == null) return const {};
    final placeholders = List.filled(deliveryIds.length, '?').join(', ');
    final rows = await database.query(
      'receipt_sends',
      where:
          'channel = ? AND delivery_id IN ($placeholders)${_usesCompanyScope ? ' AND company_id IS ?' : ''}',
      whereArgs: ['sms', ...deliveryIds, if (_usesCompanyScope) _companyId],
      orderBy: 'sent_at DESC',
    );
    final latest = <String, ReceiptSmsRecord>{};
    for (final row in rows) {
      final deliveryId = row['delivery_id']! as String;
      // Rows arrive newest first, so the first hit for a delivery is the latest.
      if (latest.containsKey(deliveryId)) continue;
      final sentAt = row['sent_at'] as String?;
      latest[deliveryId] = ReceiptSmsRecord(
        deliveryId: deliveryId,
        status: row['status']! as String,
        phone: row['phone'] as String?,
        sentAt: sentAt == null ? null : DateTime.tryParse(sentAt),
        providerReference: row['provider_reference'] as String?,
      );
    }
    return latest;
  }

  /// Saved supplier phone for a delivery, used for phone search and for the
  /// SMS recipient. Returns null when the supplier has no saved number.
  Future<String?> _supplierPhoneFor(
    String supplierId,
    String? companyId,
  ) async {
    final rows = await database.query(
      'suppliers',
      columns: ['phone'],
      where: _usesCompanyScope
          ? 'supplier_id = ? AND company_id IS ?'
          : 'supplier_id = ?',
      whereArgs: _usesCompanyScope ? [supplierId, companyId] : [supplierId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final phone = rows.first['phone'] as String?;
    return phone != null && phone.trim().isNotEmpty ? phone.trim() : null;
  }

  Future<List<Delivery>> _loadDeliveries(
    List<Map<String, Object?>> rows,
  ) async {
    final weightColumns = await database.rawQuery(
      'PRAGMA table_info(delivery_bag_weights)',
    );
    final hasWeightRecorder = weightColumns.any(
      (column) => column['name'] == 'recorded_by_user_id',
    );
    final deliveries = <Delivery>[];
    for (final row in rows) {
      final weightRows = await database.query(
        'delivery_bag_weights',
        where: _usesCompanyScope
            ? 'delivery_id = ? AND company_id = ?'
            : 'delivery_id = ?',
        whereArgs: _usesCompanyScope
            ? [row['id'], row['company_id']]
            : [row['id']],
        orderBy: 'bag_number',
      );
      final recordType = DeliveryRecordType.parse(row['record_type']);
      deliveries.add(
        Delivery(
          id: row['id']! as String,
          supplier: Supplier(
            id: row['supplier_id']! as String,
            companyId: row['company_id'] as String?,
            name: row['supplier_name']! as String,
            type: SupplierType.values.byName(row['supplier_type']! as String),
            town: '',
            district: '',
            region: '',
            phone: await _supplierPhoneFor(
              row['supplier_id']! as String,
              row['company_id'] as String?,
            ),
          ),
          product: Product(
            id: row['product_id']! as String,
            name: row['product_name']! as String,
            companyId: row['company_id'] as String?,
          ),
          recordedAt: DateTime.parse(row['recorded_at']! as String),
          bagWeights: recordType == DeliveryRecordType.bulk
              ? const <double>[]
              : weightRows
                    .map((weight) => (weight['weight']! as num).toDouble())
                    .toList(),
          recordedByUserId: _nullableUserId(row['recorded_by_user_id']),
          bagRecordedByUserIds:
              hasWeightRecorder && recordType == DeliveryRecordType.individual
              ? weightRows
                    .map(
                      (weight) =>
                          _nullableUserId(weight['recorded_by_user_id']),
                    )
                    .toList()
              : const [],
          companyId: row['company_id'] as String?,
          status: DeliveryStatus.values.byName(row['status']! as String),
          synchronizationStatus: SynchronizationStatus.values.byName(
            row['synchronization_status']! as String,
          ),
          recordType: recordType,
          bulkTotalWeight: recordType == DeliveryRecordType.bulk
              ? (row['total_weight'] as num?)?.toDouble()
              : null,
          bulkBagCount: recordType == DeliveryRecordType.bulk
              ? (row['bag_count'] as num?)?.toInt()
              : null,
          notes: row['notes'] as String?,
          updatedAt: DateTime.parse(row['updated_at']! as String),
        ),
      );
    }
    return deliveries;
  }

  static String? _nullableUserId(Object? value) {
    if (value is! String ||
        value.trim().isEmpty ||
        value == 'local-secretary') {
      return null;
    }
    return value;
  }

  void _requireActiveCompany(Delivery delivery) {
    if (!_usesCompanyScope) return;
    final activeCompanyId = _companyId;
    if (activeCompanyId == null) {
      throw StateError('Select an active company before saving deliveries.');
    }
    if (delivery.companyId != null && delivery.companyId != activeCompanyId) {
      throw StateError('Delivery belongs to a different company.');
    }
  }
}

class ReceiptSearchFilters {
  const ReceiptSearchFilters({
    this.query,
    this.phone,
    this.from,
    this.to,
    this.recorderUserId,
    this.limit = 200,
  });

  /// Matches the receipt identifier or the supplier/customer name.
  final String? query;

  /// Matches the saved supplier phone number.
  final String? phone;

  /// Inclusive start of the recorded date range.
  final DateTime? from;

  /// Exclusive end of the recorded date range.
  final DateTime? to;

  /// Restricts results to receipts recorded by this secretary/recorder.
  final String? recorderUserId;

  final int limit;

  bool get isEmpty =>
      (query == null || query!.trim().isEmpty) &&
      (phone == null || phone!.trim().isEmpty) &&
      from == null &&
      to == null &&
      (recorderUserId == null || recorderUserId!.isEmpty);
}

/// The latest recorded SMS attempt for a receipt.
class ReceiptSmsRecord {
  const ReceiptSmsRecord({
    required this.deliveryId,
    required this.status,
    this.phone,
    this.sentAt,
    this.providerReference,
  });

  final String deliveryId;

  /// 'queued' after a provider 202, 'sent' after a confirmed delivery, or
  /// 'failed'. 'queued' is never reported as delivered.
  final String status;
  final String? phone;
  final DateTime? sentAt;

  /// The provider's message identifier, when one was returned.
  final String? providerReference;

  bool get isQueued => status == 'queued';
  bool get isSent => status == 'sent';
  bool get isFailed => status == 'failed';

  /// True only when the provider confirmed the message was actually delivered.
  bool get isDelivered => isSent;

  /// User-facing status text. 'Delivered' is reserved for a confirmed send.
  String get label {
    if (isFailed) return 'Failed';
    if (isSent) return 'Sent';
    if (isQueued) return 'Queued';
    return 'Not sent';
  }
}

class DuplicateDeliveryException implements Exception {
  const DuplicateDeliveryException(this.deliveryId);

  final String deliveryId;

  @override
  String toString() => 'Delivery $deliveryId already exists';
}
