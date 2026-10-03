import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';

class DailyReport {
  const DailyReport({required this.date, required this.deliveries});

  final DateTime date;
  final List<Delivery> deliveries;

  int get supplierCount => deliveries.map((delivery) => delivery.supplier.id).toSet().length;
  int get deliveryCount => deliveries.length;
  int get totalBags => deliveries.fold(0, (total, delivery) => total + delivery.numberOfBags);
  double get totalWeight => deliveries.fold(0, (total, delivery) => total + delivery.totalWeight);

  List<ProductReportTotal> get productTotals {
    final totals = <String, ProductReportTotal>{};
    for (final delivery in deliveries) {
      final existing = totals[delivery.product.id];
      totals[delivery.product.id] = ProductReportTotal(
        productId: delivery.product.id,
        productName: delivery.product.name,
        bagCount: (existing?.bagCount ?? 0) + delivery.numberOfBags,
        totalWeight: (existing?.totalWeight ?? 0) + delivery.totalWeight,
      );
    }
    return totals.values.toList()..sort((left, right) => left.productName.compareTo(right.productName));
  }

  static String supplierTypeLabel(SupplierType type) => type == SupplierType.farmer ? 'Farmer' : 'Aggregator';
}

class ProductReportTotal {
  const ProductReportTotal({required this.productId, required this.productName, required this.bagCount, required this.totalWeight});

  final String productId;
  final String productName;
  final int bagCount;
  final double totalWeight;
}
