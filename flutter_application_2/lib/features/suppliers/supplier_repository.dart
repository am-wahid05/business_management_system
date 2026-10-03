import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';

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

  List<Supplier> get suppliers => List.unmodifiable(_suppliers);

  void clearForCompanyChange() {
    _suppliers.clear();
    _deliveries.clear();
  }

  Future<void> initialize() async {
    final db = database;
    if (db == null) return;
    if (companyIdProvider != null && _companyId == null) {
      _suppliers.clear();
      _deliveries.clear();
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
  }

  void cache(Supplier supplier) {
    final index = _suppliers.indexWhere(
      (item) => item.internalId == supplier.internalId,
    );
    if (index == -1) {
      _suppliers.add(supplier);
    } else {
      _suppliers[index] = supplier;
    }
  }

  List<Supplier> search(String query) {
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
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier;
    }
    return null;
  }

  Supplier create({
    required String name,
    required SupplierType type,
    required String phone,
    required String town,
    required String district,
    required String region,
    required String notes,
  }) {
    _requireActiveCompany();
    _validateName(name);
    final now = _now();
    final supplier = Supplier(
      id: _nextId(),
      name: name.trim(),
      type: type,
      phone: _optional(phone),
      town: town.trim(),
      district: district.trim(),
      region: region.trim(),
      companyId: _companyId,
      notes: _optional(notes),
      createdAt: now,
      updatedAt: now,
    );
    _suppliers.add(supplier);
    return supplier;
  }

  Supplier update(Supplier updatedSupplier) {
    _validateName(updatedSupplier.name, excludingId: updatedSupplier.id);
    final index = _suppliers.indexWhere(
      (supplier) => supplier.id == updatedSupplier.id,
    );
    if (index == -1)
      throw StateError('Supplier ${updatedSupplier.id} was not found');

    final updated = updatedSupplier.copyWith(updatedAt: _now());
    _suppliers[index] = updated;
    return updated;
  }

  Supplier setActive(String id, bool isActive) {
    final supplier = findById(id);
    if (supplier == null) throw StateError('Supplier $id was not found');
    return update(supplier.copyWith(isActive: isActive));
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
          if (date != null && !_sameDate(delivery.recordedAt, date))
            return false;
          if (product != null && delivery.product.id != product.id)
            return false;
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

  String _nextId() {
    var number = _suppliers.length + 1;
    while (findById('ALB-${number.toString().padLeft(6, '0')}') != null) {
      number++;
    }
    return 'ALB-${number.toString().padLeft(6, '0')}';
  }

  void _requireActiveCompany() {
    if (companyIdProvider != null && _companyId == null) {
      throw StateError('Select an active company before changing suppliers.');
    }
  }

  void _validateName(String name, {String? excludingId}) {
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required');
    final duplicate = _suppliers.where((supplier) {
      return supplier.id != excludingId &&
          _normalize(supplier.name) == _normalize(name);
    });
    if (duplicate.isNotEmpty) {
      throw StateError('A supplier with this name already exists');
    }
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
