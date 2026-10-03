import '../../domain/models/delivery.dart';
import '../../domain/models/supplier.dart';
import '../receiving/delivery_repository.dart';

class SupplierStatement {
  const SupplierStatement({
    required this.supplier,
    required this.from,
    required this.to,
    required this.deliveries,
  });

  final Supplier supplier;
  final DateTime from;
  final DateTime to;
  final List<Delivery> deliveries;

  int get totalBags =>
      deliveries.fold(0, (total, delivery) => total + delivery.numberOfBags);

  double get totalWeight => deliveries.fold(
        0,
        (total, delivery) => total + delivery.totalWeight,
      );
}

class SupplierStatementService {
  SupplierStatementService(this.deliveryRepository);

  final DeliveryRepository deliveryRepository;

  Future<SupplierStatement> build({
    required Supplier supplier,
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = DateTime(to.year, to.month, to.day + 1);
    if (endExclusive.isBefore(start)) {
      throw ArgumentError.value(to, 'to', 'must not be before from');
    }
    final deliveries = await deliveryRepository.forRange(
      start,
      endExclusive,
      supplierId: supplier.id,
    );
    return SupplierStatement(
      supplier: supplier,
      from: start,
      to: DateTime(to.year, to.month, to.day),
      deliveries: List.unmodifiable(deliveries),
    );
  }
}

abstract interface class SupplierStatementExporter {
  Future<Object> export(SupplierStatement statement);
}


