import 'package:sqflite/sqflite.dart';

import 'analytics_models.dart';

class AnalyticsRepository {
  AnalyticsRepository(this.database, {this.companyIdProvider});

  final Database database;
  final String? Function()? companyIdProvider;

  Future<AnalyticsSummary> summary(AnalyticsFilters filters) async {
    final query = _query(filters);
    final row = (await database.rawQuery('''
      SELECT
        COUNT(DISTINCT d.id) AS delivery_count,
        COUNT(w.delivery_id) AS total_bags,
        COALESCE(SUM(w.weight), 0) AS total_weight,
        COUNT(DISTINCT d.supplier_id) AS unique_suppliers,
        COUNT(DISTINCT CASE WHEN d.supplier_type = 'farmer' THEN d.supplier_id END) AS unique_farmers,
        COUNT(DISTINCT CASE WHEN d.supplier_type = 'aggregator' THEN d.supplier_id END) AS unique_aggregators,
        COUNT(DISTINCT CASE WHEN s.is_active = 1 THEN d.supplier_id END) AS active_suppliers,
        COUNT(DISTINCT d.product_id) AS product_count
      FROM deliveries d
      LEFT JOIN delivery_bag_weights w ON w.delivery_id = d.id AND w.company_id IS d.company_id AND w.weight > 0
      LEFT JOIN suppliers s ON s.supplier_id = d.supplier_id AND s.company_id IS d.company_id
      WHERE ${query.where}
    ''', query.arguments)).single;
    return AnalyticsSummary(
      deliveryCount: _int(row['delivery_count']),
      totalBags: _int(row['total_bags']),
      totalWeight: _double(row['total_weight']),
      uniqueSuppliers: _int(row['unique_suppliers']),
      uniqueFarmers: _int(row['unique_farmers']),
      uniqueAggregators: _int(row['unique_aggregators']),
      activeSuppliers: _int(row['active_suppliers']),
      productCount: _int(row['product_count']),
    );
  }

  Future<List<ProductAnalyticsTotal>> productBreakdown(
    AnalyticsFilters filters,
  ) async {
    final query = _query(filters);
    final rows = await database.rawQuery('''
      SELECT
        d.product_id,
        d.product_name,
        COUNT(DISTINCT d.id) AS delivery_count,
        COUNT(w.delivery_id) AS total_bags,
        COALESCE(SUM(w.weight), 0) AS total_weight,
        COUNT(DISTINCT d.supplier_id) AS unique_suppliers
      FROM deliveries d
      LEFT JOIN delivery_bag_weights w ON w.delivery_id = d.id AND w.company_id IS d.company_id AND w.weight > 0
      LEFT JOIN suppliers s ON s.supplier_id = d.supplier_id AND s.company_id IS d.company_id
      WHERE ${query.where}
      GROUP BY d.product_id, d.product_name
      ORDER BY total_weight DESC, d.product_name COLLATE NOCASE
    ''', query.arguments);
    return rows
        .map(
          (row) => ProductAnalyticsTotal(
            productId: row['product_id']! as String,
            productName: row['product_name']! as String,
            deliveryCount: _int(row['delivery_count']),
            totalBags: _int(row['total_bags']),
            totalWeight: _double(row['total_weight']),
            uniqueSuppliers: _int(row['unique_suppliers']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<SupplierAnalyticsTotal>> supplierBreakdown(
    AnalyticsFilters filters,
  ) async {
    final query = _query(filters);
    final rows = await database.rawQuery('''
      SELECT
        d.supplier_id,
        MAX(d.supplier_name) AS supplier_name,
        MAX(d.supplier_type) AS supplier_type,
        COUNT(DISTINCT d.id) AS delivery_count,
        COUNT(w.delivery_id) AS total_bags,
        COALESCE(SUM(w.weight), 0) AS total_weight
      FROM deliveries d
      LEFT JOIN delivery_bag_weights w ON w.delivery_id = d.id AND w.company_id IS d.company_id AND w.weight > 0
      LEFT JOIN suppliers s ON s.supplier_id = d.supplier_id AND s.company_id IS d.company_id
      WHERE ${query.where}
      GROUP BY d.supplier_id
      ORDER BY total_weight DESC, supplier_name COLLATE NOCASE
    ''', query.arguments);
    return rows
        .map(
          (row) => SupplierAnalyticsTotal(
            supplierId: row['supplier_id']! as String,
            supplierName: row['supplier_name']! as String,
            supplierType: row['supplier_type']! as String,
            deliveryCount: _int(row['delivery_count']),
            totalBags: _int(row['total_bags']),
            totalWeight: _double(row['total_weight']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<AnalyticsTrendTotal>> trend(
    AnalyticsFilters filters,
    AnalyticsTrend trend,
  ) async {
    final query = _query(filters);
    final expression = switch (trend) {
      AnalyticsTrend.daily => "substr(d.recorded_at, 1, 10)",
      AnalyticsTrend.weekly => "strftime('%Y-W%W', d.recorded_at)",
      AnalyticsTrend.monthly => "substr(d.recorded_at, 1, 7)",
      AnalyticsTrend.yearly => "substr(d.recorded_at, 1, 4)",
    };
    final rows = await database.rawQuery('''
      SELECT
        $expression AS period,
        COUNT(DISTINCT d.id) AS delivery_count,
        COUNT(w.delivery_id) AS total_bags,
        COALESCE(SUM(w.weight), 0) AS total_weight
      FROM deliveries d
      LEFT JOIN delivery_bag_weights w ON w.delivery_id = d.id AND w.company_id IS d.company_id AND w.weight > 0
      LEFT JOIN suppliers s ON s.supplier_id = d.supplier_id AND s.company_id IS d.company_id
      WHERE ${query.where}
      GROUP BY period
      ORDER BY period
    ''', query.arguments);
    return rows
        .map(
          (row) => AnalyticsTrendTotal(
            period: row['period']! as String,
            deliveryCount: _int(row['delivery_count']),
            totalBags: _int(row['total_bags']),
            totalWeight: _double(row['total_weight']),
          ),
        )
        .toList(growable: false);
  }

  Future<SupplierActivitySummary> supplierActivity(
    AnalyticsFilters filters,
  ) async {
    final query = _query(filters);
    final row = (await database.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT CASE WHEN first_delivery.first_recorded_at >= ? AND first_delivery.first_recorded_at < ? THEN d.supplier_id END) AS new_suppliers,
        COUNT(DISTINCT CASE WHEN first_delivery.first_recorded_at < ? THEN d.supplier_id END) AS returning_suppliers
      FROM deliveries d
      LEFT JOIN suppliers s ON s.supplier_id = d.supplier_id AND s.company_id IS d.company_id
      LEFT JOIN (SELECT company_id, supplier_id, MIN(recorded_at) AS first_recorded_at FROM deliveries WHERE status != 'cancelled' GROUP BY company_id, supplier_id) first_delivery ON first_delivery.company_id IS d.company_id AND first_delivery.supplier_id = d.supplier_id
      WHERE ${query.where}
    ''',
      [
        query.arguments[0],
        query.arguments[1],
        query.arguments[0],
        ...query.arguments,
      ],
    )).single;
    return SupplierActivitySummary(
      newSuppliers: _int(row['new_suppliers']),
      returningSuppliers: _int(row['returning_suppliers']),
    );
  }

  Future<List<LocationAnalyticsTotal>> locationBreakdown(
    AnalyticsFilters filters, {
    String field = 'town',
  }) async {
    final query = _query(filters);
    final column = switch (field) {
      'district' => 's.district',
      'region' => 's.region',
      _ => 's.town',
    };
    final rows = await database.rawQuery('''
      SELECT $column AS location, COUNT(DISTINCT d.supplier_id) AS supplier_count,
        COUNT(DISTINCT d.id) AS delivery_count, COUNT(w.delivery_id) AS total_bags,
        COALESCE(SUM(w.weight), 0) AS total_weight
      FROM deliveries d
      LEFT JOIN delivery_bag_weights w ON w.delivery_id = d.id AND w.company_id IS d.company_id AND w.weight > 0
      LEFT JOIN suppliers s ON s.supplier_id = d.supplier_id AND s.company_id IS d.company_id
      WHERE ${query.where} AND $column IS NOT NULL AND TRIM($column) != ''
      GROUP BY $column
      ORDER BY total_weight DESC
    ''', query.arguments);
    return rows
        .map(
          (row) => LocationAnalyticsTotal(
            location: row['location']! as String,
            supplierCount: _int(row['supplier_count']),
            deliveryCount: _int(row['delivery_count']),
            totalBags: _int(row['total_bags']),
            totalWeight: _double(row['total_weight']),
          ),
        )
        .toList(growable: false);
  }

  _AnalyticsQuery _query(AnalyticsFilters filters) {
    final clauses = <String>[
      "d.recorded_at >= ?",
      "d.recorded_at < ?",
      "d.status != 'cancelled'",
    ];
    final arguments = <Object?>[
      _startOfDay(filters.from).toIso8601String(),
      _startOfDay(filters.to).add(const Duration(days: 1)).toIso8601String(),
    ];
    void add(String clause, Object? value) {
      if (value == null || (value is String && value.trim().isEmpty)) return;
      clauses.add(clause);
      arguments.add(value);
    }

    add('d.product_id = ?', filters.productId);
    add('d.supplier_id = ?', filters.supplierId);
    add('d.supplier_type = ?', filters.supplierType);
    add('s.town = ?', filters.town);
    add('s.district = ?', filters.district);
    add('s.region = ?', filters.region);
    if (companyIdProvider != null) {
      final companyId = companyIdProvider!();
      if (companyId == null) {
        clauses.add('1 = 0');
      } else {
        clauses.add('d.company_id = ?');
        arguments.add(companyId);
      }
    }
    return _AnalyticsQuery(clauses.join(' AND '), arguments);
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;
  static double _double(Object? value) => (value as num?)?.toDouble() ?? 0;
}

class _AnalyticsQuery {
  const _AnalyticsQuery(this.where, this.arguments);

  final String where;
  final List<Object?> arguments;
}
