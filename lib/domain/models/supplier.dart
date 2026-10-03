enum SupplierType { farmer, aggregator }

class Supplier {
  Supplier({
    required this.id,
    required this.name,
    required this.type,
    required this.town,
    required this.district,
    required this.region,
    this.companyId,
    this.phone,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isActive = true,
    String? internalId,
  }) : internalId = internalId ?? id,
       createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       updatedAt =
           updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String internalId;
  final String id;
  final String name;
  final SupplierType type;
  final String town;
  final String district;
  final String region;
  final String? companyId;
  final String? phone;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  Supplier copyWith({
    String? name,
    SupplierType? type,
    String? town,
    String? district,
    String? region,
    String? phone,
    String? notes,
    DateTime? updatedAt,
    bool? isActive,
    String? internalId,
  }) {
    return Supplier(
      internalId: internalId ?? this.internalId,
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      town: town ?? this.town,
      district: district ?? this.district,
      region: region ?? this.region,
      companyId: companyId,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
