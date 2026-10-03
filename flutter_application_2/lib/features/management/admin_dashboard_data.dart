import '../../domain/models/delivery.dart';

class AdminDashboardData {
  const AdminDashboardData(this.deliveries, {this.recorderNames = const {}});

  final List<Delivery> deliveries;
  final Map<String, String> recorderNames;

  String recorderName(String? userId) =>
      recorderDisplayName(userId, recorderNames);

  int get supplierCount =>
      deliveries.map((delivery) => delivery.supplier.id).toSet().length;
  int get deliveryCount => deliveries.length;
  int get bagCount =>
      deliveries.fold(0, (total, delivery) => total + delivery.numberOfBags);
  double get totalWeight =>
      deliveries.fold(0, (total, delivery) => total + delivery.totalWeight);

  Map<String, AdminProductTotal> get productTotals {
    final totals = <String, AdminProductTotal>{};
    for (final delivery in deliveries) {
      final current = totals[delivery.product.id];
      totals[delivery.product.id] = AdminProductTotal(
        name: delivery.product.name,
        bags: (current?.bags ?? 0) + delivery.numberOfBags,
        weight: (current?.weight ?? 0) + delivery.totalWeight,
      );
    }
    return totals;
  }

  Map<String, int> get synchronizationTotals {
    final totals = <String, int>{};
    for (final delivery in deliveries) {
      totals.update(
        delivery.synchronizationStatus.name,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return totals;
  }
}

class AdminProductTotal {
  const AdminProductTotal({
    required this.name,
    required this.bags,
    required this.weight,
  });

  final String name;
  final int bags;
  final double weight;
}
