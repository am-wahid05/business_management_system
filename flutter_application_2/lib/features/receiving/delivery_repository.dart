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
    if (hasSupplierInternalId)
      row['supplier_internal_id'] = delivery.supplier.internalId;
    if (columns.any((column) => column['name'] == 'company_id')) {
      row['company_id'] = _usesCompanyScope ? _companyId : delivery.companyId;
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
          ),
          product: Product(
            id: row['product_id']! as String,
            name: row['product_name']! as String,
            companyId: row['company_id'] as String?,
          ),
          recordedAt: DateTime.parse(row['recorded_at']! as String),
          bagWeights: weightRows
              .map((weight) => (weight['weight']! as num).toDouble())
              .toList(),
          recordedByUserId: _nullableUserId(row['recorded_by_user_id']),
          bagRecordedByUserIds: hasWeightRecorder
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

class DuplicateDeliveryException implements Exception {
  const DuplicateDeliveryException(this.deliveryId);

  final String deliveryId;

  @override
  String toString() => 'Delivery $deliveryId already exists';
}
