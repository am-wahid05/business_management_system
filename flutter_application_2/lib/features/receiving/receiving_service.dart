import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';
import '../suppliers/supplier_repository.dart';
import 'delivery_repository.dart';

class ReceivingService {
  ReceivingService({
    required this.database,
    required this.supplierRepository,
    this.companyIdProvider,
    this.userIdProvider,
  });

  final Database database;
  final SupplierRepository supplierRepository;
  final String? Function()? companyIdProvider;
  final String? Function()? userIdProvider;
  String? get currentUserId => userIdProvider?.call();
  String? get _companyId => companyIdProvider?.call();

  Future<Delivery> saveDelivery({
    String? supplierId,
    required String supplierName,
    required SupplierType supplierType,
    required String town,
    required String district,
    required String region,
    String? phone,
    String? notes,
    Supplier? selectedSupplier,
    required Delivery delivery,
  }) async {
    final authenticatedUserId = currentUserId;
    if (userIdProvider != null && authenticatedUserId == null) {
      throw StateError('Sign in before recording a delivery.');
    }
    if (authenticatedUserId != null &&
        delivery.recordedByUserId != null &&
        delivery.recordedByUserId != authenticatedUserId) {
      throw StateError('A delivery must be recorded by the signed-in user.');
    }
    if (authenticatedUserId != null &&
        delivery.bagRecordedByUserIds.any(
          (recordedBy) =>
              recordedBy != null && recordedBy != authenticatedUserId,
        )) {
      throw StateError('Bag weights must be recorded by the signed-in user.');
    }
    delivery = delivery.copyWith(
      recordedByUserId: authenticatedUserId ?? delivery.recordedByUserId,
      bagRecordedByUserIds: authenticatedUserId != null
          ? List<String?>.filled(
              delivery.bagWeights.length,
              authenticatedUserId,
            )
          : delivery.bagRecordedByUserIds,
      companyId: delivery.companyId ?? _companyId,
    );
    if (companyIdProvider != null && _companyId == null) {
      throw StateError('Select an active company before recording a delivery.');
    }
    if (companyIdProvider != null &&
        selectedSupplier != null &&
        selectedSupplier.companyId != _companyId) {
      throw StateError('Supplier belongs to a different company.');
    }
    if (companyIdProvider != null &&
        delivery.companyId != null &&
        delivery.companyId != _companyId) {
      throw StateError('Delivery belongs to a different company.');
    }
    return database.transaction((transaction) async {
      var supplier = selectedSupplier;
      final normalizedName = SupplierRepository.normalizeName(supplierName);
      if (supplier == null) {
        final supplierArguments = <Object?>[];
        if (companyIdProvider != null) supplierArguments.add(_companyId);
        if (supplierId == null || supplierId.trim().isEmpty) {
          supplierArguments.add(normalizedName);
        } else {
          supplierArguments
            ..add(supplierId.trim())
            ..add(normalizedName);
        }
        final existing = await transaction.query(
          'suppliers',
          where:
              '${companyIdProvider == null ? '' : 'company_id IS ? AND '}${supplierId == null || supplierId.trim().isEmpty ? 'normalized_name = ? AND is_active = 1' : '(supplier_id = ? OR normalized_name = ?) AND is_active = 1'}',
          whereArgs: supplierArguments,
          limit: 1,
        );
        supplier = existing.isEmpty
            ? null
            : SupplierRepository.fromRow(existing.single);
      }
      supplier ??= await _createSupplier(
        transaction,
        supplierName,
        supplierType,
        town,
        district,
        region,
        phone,
        notes,
      );
      if (supplier.internalId != delivery.supplier.internalId) {
        delivery = delivery.copyWith(supplier: supplier);
      }
      final repository = DeliveryRepository(
        database,
        companyIdProvider: companyIdProvider,
        userIdProvider: userIdProvider,
      );
      await repository.saveInTransaction(transaction, delivery);
      supplierRepository.cache(supplier);
      return delivery;
    });
  }

  Future<Supplier> _createSupplier(
    DatabaseExecutor transaction,
    String name,
    SupplierType type,
    String town,
    String district,
    String region,
    String? phone,
    String? notes,
  ) async {
    final now = DateTime.now();
    final internalId = _uuid();
    final namespace = await _metadata(
      transaction,
      'supplier_device_namespace',
      () => _namespace(),
    );
    final counter =
        int.parse(await _metadata(transaction, 'supplier_counter', () => '0')) +
        1;
    await transaction.insert('local_metadata', {
      'key': 'supplier_counter',
      'value': '$counter',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final supplier = Supplier(
      internalId: internalId,
      id: 'ALB-$namespace-${counter.toString().padLeft(6, '0')}',
      name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
      type: type,
      town: town.trim(),
      district: district.trim(),
      region: region.trim(),
      companyId: _companyId,
      phone: _optional(phone),
      notes: _optional(notes),
      createdAt: now,
      updatedAt: now,
    );
    await transaction.insert('suppliers', SupplierRepository.toRow(supplier));
    return supplier;
  }

  Future<String> _metadata(
    DatabaseExecutor transaction,
    String key,
    String Function() create,
  ) async {
    final rows = await transaction.query(
      'local_metadata',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['value']! as String;
    final value = create();
    await transaction.insert('local_metadata', {'key': key, 'value': value});
    return value;
  }

  static String _namespace() => List.generate(
    6,
    (_) => Random.secure().nextInt(36).toRadixString(36),
  ).join().toUpperCase();
  static String _uuid() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static String? _optional(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
