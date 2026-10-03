import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';
import '../suppliers/supplier_repository.dart';
import 'sync_models.dart';

class SupabaseDeliveryStore implements CompanyCatalogStore {
  SupabaseDeliveryStore(
    this.client, {
    required this.localDatabase,
    required this.companyId,
    required this.userId,
    required this.isAdmin,
  });

  final SupabaseClient client;
  final Database localDatabase;
  final String? Function() companyId;
  final String? Function() userId;
  final bool Function() isAdmin;

  @override
  Future<void> synchronizeCatalog() async {
    final activeCompanyId = companyId();
    if (activeCompanyId == null)
      throw StateError('Select a company before synchronizing.');
    final supplierRows = await localDatabase.query(
      'suppliers',
      where: 'company_id = ?',
      whereArgs: [activeCompanyId],
    );
    for (final row in supplierRows) {
      await client.from('suppliers').upsert({
        'id': row['supplier_id'],
        'supplier_id': row['supplier_id'],
        'company_id': activeCompanyId,
        'normalized_name': row['normalized_name'],
        'name': row['name'],
        'type': row['type'] == 'aggregator' ? 'company' : 'farmer',
        'phone': row['phone'],
        'town': row['town'],
        'district': row['district'],
        'region': row['region'],
        'notes': row['notes'],
        'is_active': row['is_active'] == 1,
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      }, onConflict: 'company_id,id');
    }
    if (isAdmin()) {
      final productRows = await localDatabase.query(
        'products',
        where: 'company_id = ?',
        whereArgs: [activeCompanyId],
      );
      for (final row in productRows) {
        await client.from('products').upsert({
          'id': row['id'],
          'company_id': activeCompanyId,
          'name': row['name'],
          'is_active': row['is_active'] == 1,
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
        }, onConflict: 'company_id,id');
      }
    }
  }

  @override
  Future<void> downloadCompany() async {
    final activeCompanyId = companyId();
    if (activeCompanyId == null)
      throw StateError('Select a company before synchronizing.');
    final remoteSuppliers = await _allRows('suppliers', activeCompanyId);
    final remoteProducts = await _allRows('products', activeCompanyId);
    final remoteDeliveries = await _allRows('deliveries', activeCompanyId);
    final remoteWeights = await _allRows(
      'delivery_bag_weights',
      activeCompanyId,
    );
    await localDatabase.transaction((transaction) async {
      for (final row in remoteSuppliers) {
        await transaction.insert('suppliers', {
          'internal_id': '$activeCompanyId:${row['supplier_id']}',
          'supplier_id': row['supplier_id'],
          'company_id': activeCompanyId,
          'normalized_name': row['normalized_name'],
          'name': row['name'],
          'type': row['type'] == 'company' ? 'aggregator' : 'farmer',
          'phone': row['phone'],
          'town': row['town'] ?? '',
          'district': row['district'] ?? '',
          'region': row['region'] ?? '',
          'notes': row['notes'],
          'is_active': row['is_active'] == true ? 1 : 0,
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
          'synchronization_status': 'synced',
          'synchronization_error': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in remoteProducts) {
        await transaction.insert('products', {
          'id': row['id'],
          'company_id': activeCompanyId,
          'name': row['name'],
          'is_active': row['is_active'] == true ? 1 : 0,
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in remoteDeliveries) {
        final current = await transaction.query(
          'deliveries',
          where: 'id = ? AND company_id = ?',
          whereArgs: [row['id'], activeCompanyId],
          limit: 1,
        );
        if (current.isNotEmpty &&
            const [
              'pendingSync',
              'pending',
              'syncFailed',
              'localOnly',
            ].contains(current.single['synchronization_status']))
          continue;
        await transaction.insert('deliveries', {
          'id': row['id'],
          'supplier_id': row['supplier_id'],
          'product_id': row['product_id'],
          'recorded_at': row['recorded_at'],
          'recorded_by_user_id': row['recorded_by_user_id'],
          'company_id': activeCompanyId,
          'status': row['status'],
          'synchronization_status': 'synced',
          'supplier_name': row['supplier_name'],
          'product_name': row['product_name'],
          'supplier_type': row['supplier_type'] == 'company'
              ? 'aggregator'
              : 'farmer',
          'synchronization_error': null,
          'sync_attempts': 0,
          'synced_at': row['updated_at'],
          'created_at': row['created_at'] ?? row['recorded_at'],
          'updated_at': row['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.delete(
          'delivery_bag_weights',
          where: 'delivery_id = ? AND company_id = ?',
          whereArgs: [row['id'], activeCompanyId],
        );
        for (final weight in remoteWeights.where(
          (weight) => weight['delivery_id'] == row['id'],
        )) {
          await transaction.insert('delivery_bag_weights', {
            'delivery_id': row['id'],
            'company_id': activeCompanyId,
            'bag_number': weight['bag_number'],
            'weight': (weight['weight'] as num).toDouble(),
            'recorded_by_user_id': weight['recorded_by_user_id'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> _allRows(
    String table,
    String activeCompanyId,
  ) async {
    const pageSize = 1000;
    final result = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = await client
          .from(table)
          .select()
          .eq('company_id', activeCompanyId)
          .range(start, start + pageSize - 1);
      result.addAll((page as List).cast<Map<String, dynamic>>());
      if (page.length < pageSize) return result;
      start += pageSize;
    }
  }

  @override
  Future<void> upsert(Delivery delivery) async {
    final activeCompanyId = companyId();
    final activeUserId = userId();
    if (activeCompanyId == null || activeUserId == null) {
      throw StateError('Sign in to a company before synchronizing records.');
    }

    final localSupplierRows = await localDatabase.query(
      'suppliers',
      where: 'company_id = ? AND supplier_id = ?',
      whereArgs: [activeCompanyId, delivery.supplier.id],
      limit: 1,
    );
    final supplierRow = localSupplierRows.isEmpty
        ? null
        : localSupplierRows.single;
    await client.from('suppliers').upsert({
      'id': delivery.supplier.id,
      'supplier_id': delivery.supplier.id,
      'company_id': activeCompanyId,
      'normalized_name': SupplierRepository.normalizeName(
        (supplierRow?['name'] as String?) ?? delivery.supplier.name,
      ),
      'name': supplierRow?['name'] ?? delivery.supplier.name,
      'type':
          (supplierRow?['type'] as String?) == 'aggregator' ||
              delivery.supplier.type == SupplierType.aggregator
          ? 'company'
          : 'farmer',
      'town': supplierRow?['town'] ?? delivery.supplier.town,
      'district': supplierRow?['district'] ?? delivery.supplier.district,
      'region': supplierRow?['region'] ?? delivery.supplier.region,
      'phone': supplierRow?['phone'] ?? delivery.supplier.phone,
      'notes': supplierRow?['notes'] ?? delivery.supplier.notes,
      'is_active': supplierRow == null
          ? delivery.supplier.isActive
          : supplierRow['is_active'] == 1,
      'created_at':
          supplierRow?['created_at'] ??
          delivery.supplier.createdAt.toUtc().toIso8601String(),
      'updated_at':
          supplierRow?['updated_at'] ??
          delivery.supplier.updatedAt.toUtc().toIso8601String(),
    }, onConflict: 'company_id,id');

    final product = await client
        .from('products')
        .select('id')
        .eq('company_id', activeCompanyId)
        .eq('id', delivery.product.id)
        .maybeSingle();
    if (product == null) {
      throw StateError(
        'Product ${delivery.product.name} is not configured for this company.',
      );
    }

    final existing = await client
        .from('deliveries')
        .select('updated_at, recorded_by_user_id')
        .eq('id', delivery.id)
        .eq('company_id', activeCompanyId)
        .maybeSingle();
    if (existing == null &&
        (delivery.recordedByUserId == null ||
            delivery.recordedByUserId != activeUserId)) {
      throw StateError(
        'This unassigned or previously recorded delivery cannot be attributed to the current user during sync.',
      );
    }
    if (existing != null) {
      final remoteUpdatedAt = DateTime.parse(existing['updated_at'] as String);
      if (remoteUpdatedAt.isAfter(delivery.updatedAt)) {
        throw SyncConflictException(
          delivery.id,
          'Remote delivery is newer than the local record',
        );
      }
    }
    final remoteWeights =
        await client
                .from('delivery_bag_weights')
                .select('bag_number, recorded_by_user_id')
                .eq('company_id', activeCompanyId)
                .eq('delivery_id', delivery.id)
            as List;
    final remoteWeightsByNumber = {
      for (final raw in remoteWeights.cast<Map<String, dynamic>>())
        raw['bag_number'] as int: raw,
    };
    for (var index = 0; index < delivery.bagWeights.length; index++) {
      final number = index + 1;
      if (!remoteWeightsByNumber.containsKey(number) &&
          delivery.recorderForBag(index) != activeUserId) {
        throw StateError(
          'Bag $number has no authenticated recorder and will not be attributed during sync.',
        );
      }
    }
    final deliveryPayload = <String, Object?>{
      'id': delivery.id,
      'company_id': activeCompanyId,
      'supplier_id': delivery.supplier.id,
      'supplier_name': delivery.supplier.name,
      'supplier_type':
          (supplierRow?['type'] as String?) == 'aggregator' ||
              delivery.supplier.type == SupplierType.aggregator
          ? 'company'
          : 'farmer',
      'product_id': delivery.product.id,
      'product_name': delivery.product.name,
      'recorded_at': delivery.recordedAt.toIso8601String(),
      'status': delivery.status.name,
      'updated_at': delivery.updatedAt.toIso8601String(),
    };
    if (existing == null) {
      deliveryPayload['recorded_by_user_id'] = delivery.recordedByUserId;
    }
    await client
        .from('deliveries')
        .upsert(deliveryPayload, onConflict: 'company_id,id');

    for (final raw in remoteWeights.cast<Map<String, dynamic>>()) {
      final number = raw['bag_number'] as int;
      if (number > delivery.bagWeights.length) {
        await client
            .from('delivery_bag_weights')
            .delete()
            .eq('company_id', activeCompanyId)
            .eq('delivery_id', delivery.id)
            .eq('bag_number', number);
      }
    }
    for (var index = 0; index < delivery.bagWeights.length; index++) {
      final number = index + 1;
      final remoteWeight = remoteWeightsByNumber[number];
      if (remoteWeight != null) {
        // Updating a weight never replaces its immutable recorder identity.
        await client
            .from('delivery_bag_weights')
            .update({'weight': delivery.bagWeights[index]})
            .eq('company_id', activeCompanyId)
            .eq('delivery_id', delivery.id)
            .eq('bag_number', number);
      } else {
        await client.from('delivery_bag_weights').insert({
          'company_id': activeCompanyId,
          'delivery_id': delivery.id,
          'bag_number': number,
          'weight': delivery.bagWeights[index],
          'recorded_by_user_id': delivery.recorderForBag(index),
        });
      }
    }
  }
}

class SyncConflictException implements Exception {
  const SyncConflictException(this.deliveryId, this.message);

  final String deliveryId;
  final String message;

  @override
  String toString() => 'Sync conflict for $deliveryId: $message';
}
