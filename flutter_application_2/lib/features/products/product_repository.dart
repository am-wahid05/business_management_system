import 'package:sqflite/sqflite.dart';

import '../../domain/models/product.dart';

class ProductRepository {
  ProductRepository(this.database, {this.companyIdProvider});

  final Database database;
  final String? Function()? companyIdProvider;

  String? get _companyId => companyIdProvider?.call();
  bool get _usesCompanyScope => companyIdProvider != null;

  Future<void> seedInitialProducts() async {
    if (_usesCompanyScope && _companyId == null) return;
    final now = DateTime.now().toIso8601String();
    for (final product in Product.initialProducts) {
      final companyId = _companyId;
      final existing = await database.query(
        'products',
        where: !_usesCompanyScope
            ? 'id = ?'
            : companyId == null
            ? 'id = ? AND company_id IS NULL'
            : 'id = ? AND company_id = ?',
        whereArgs: !_usesCompanyScope
            ? [product.id]
            : companyId == null
            ? [product.id]
            : [product.id, companyId],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      await database.insert('products', {
        'id': product.id,
        if (_usesCompanyScope) 'company_id': companyId,
        'name': product.name,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<Product>> all({bool activeOnly = false}) async {
    if (_usesCompanyScope && _companyId == null) return const [];
    final rows = await database.query(
      'products',
      where: !_usesCompanyScope
          ? (activeOnly ? 'is_active = ?' : null)
          : _companyId == null
          ? (activeOnly
                ? 'company_id IS NULL AND is_active = ?'
                : 'company_id IS NULL')
          : (activeOnly
                ? 'company_id = ? AND is_active = ?'
                : 'company_id = ?'),
      whereArgs: !_usesCompanyScope
          ? (activeOnly ? [1] : null)
          : _companyId == null
          ? (activeOnly ? [1] : null)
          : (activeOnly ? [_companyId, 1] : [_companyId]),
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<Product?> findById(String id) async {
    if (_usesCompanyScope && _companyId == null) return null;
    final rows = await database.query(
      'products',
      where: !_usesCompanyScope
          ? 'id = ?'
          : _companyId == null
          ? 'id = ? AND company_id IS NULL'
          : 'id = ? AND company_id = ?',
      whereArgs: !_usesCompanyScope
          ? [id]
          : _companyId == null
          ? [id]
          : [id, _companyId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Product> create(String name) async {
    _requireActiveCompany();
    final cleanName = _validateName(name);
    final now = DateTime.now();
    final id = _newId(cleanName);
    try {
      await database.insert('products', {
        'id': id,
        if (_usesCompanyScope) 'company_id': _companyId,
        'name': cleanName,
        'is_active': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError())
        throw StateError('A product with this name already exists');
      rethrow;
    }
    return (await findById(id))!;
  }

  Future<Product> update(Product product) async {
    _requireActiveCompany();
    final cleanName = _validateName(product.name);
    try {
      final changed = await database.update(
        'products',
        {
          'name': cleanName,
          'is_active': product.isActive ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: !_usesCompanyScope
            ? 'id = ?'
            : _companyId == null
            ? 'id = ? AND company_id IS NULL'
            : 'id = ? AND company_id = ?',
        whereArgs: !_usesCompanyScope
            ? [product.id]
            : _companyId == null
            ? [product.id]
            : [product.id, _companyId],
      );
      if (changed == 0) throw StateError('Product ${product.id} was not found');
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError())
        throw StateError('A product with this name already exists');
      rethrow;
    }
    return (await findById(product.id))!;
  }

  Future<Product> setActive(Product product, bool isActive) {
    return update(product.copyWith(isActive: isActive));
  }

  String _validateName(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Product name is required');
    return cleanName;
  }

  void _requireActiveCompany() {
    if (_usesCompanyScope && _companyId == null) {
      throw StateError('Select an active company before changing products.');
    }
  }

  String _newId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '$slug-${DateTime.now().microsecondsSinceEpoch}';
  }

  static Product _fromRow(Map<String, Object?> row) {
    return Product(
      id: row['id']! as String,
      companyId: row['company_id'] as String?,
      name: row['name']! as String,
      isActive: row['is_active'] == 1,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }
}
