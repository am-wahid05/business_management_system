enum AnalyticsTrend { daily, weekly, monthly, yearly }

class AnalyticsFilters {
  const AnalyticsFilters({
    required this.from,
    required this.to,
    this.productId,
    this.supplierId,
    this.supplierType,
    this.town,
    this.district,
    this.region,
  });

  final DateTime from;
  final DateTime to;
  final String? productId;
  final String? supplierId;
  final String? supplierType;
  final String? town;
  final String? district;
  final String? region;
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.deliveryCount,
    required this.totalBags,
    required this.totalWeight,
    required this.uniqueSuppliers,
    required this.uniqueFarmers,
    required this.uniqueAggregators,
    required this.activeSuppliers,
    required this.productCount,
  });

  final int deliveryCount;
  final int totalBags;
  final double totalWeight;
  final int uniqueSuppliers;
  final int uniqueFarmers;
  final int uniqueAggregators;
  final int activeSuppliers;
  final int productCount;

  double get averageWeightPerDelivery =>
      deliveryCount == 0 ? 0 : totalWeight / deliveryCount;
  double get averageWeightPerBag => totalBags == 0 ? 0 : totalWeight / totalBags;
  double get averageBagsPerDelivery =>
      deliveryCount == 0 ? 0 : totalBags / deliveryCount;
}

class ProductAnalyticsTotal {
  const ProductAnalyticsTotal({
    required this.productId,
    required this.productName,
    required this.deliveryCount,
    required this.totalBags,
    required this.totalWeight,
    required this.uniqueSuppliers,
  });

  final String productId;
  final String productName;
  final int deliveryCount;
  final int totalBags;
  final double totalWeight;
  final int uniqueSuppliers;

  double get averageWeightPerDelivery =>
      deliveryCount == 0 ? 0 : totalWeight / deliveryCount;
  double get averageWeightPerBag => totalBags == 0 ? 0 : totalWeight / totalBags;
}

class SupplierAnalyticsTotal {
  const SupplierAnalyticsTotal({
    required this.supplierId,
    required this.supplierName,
    required this.supplierType,
    required this.deliveryCount,
    required this.totalBags,
    required this.totalWeight,
  });

  final String supplierId;
  final String supplierName;
  final String supplierType;
  final int deliveryCount;
  final int totalBags;
  final double totalWeight;
}

class AnalyticsTrendTotal {
  const AnalyticsTrendTotal({
    required this.period,
    required this.deliveryCount,
    required this.totalBags,
    required this.totalWeight,
  });

  final String period;
  final int deliveryCount;
  final int totalBags;
  final double totalWeight;
}

class SupplierActivitySummary {
  const SupplierActivitySummary({required this.newSuppliers, required this.returningSuppliers});

  final int newSuppliers;
  final int returningSuppliers;
}

class LocationAnalyticsTotal {
  const LocationAnalyticsTotal({required this.location, required this.supplierCount, required this.deliveryCount, required this.totalBags, required this.totalWeight});

  final String location;
  final int supplierCount;
  final int deliveryCount;
  final int totalBags;
  final double totalWeight;
}
