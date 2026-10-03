class Product {
  Product({
    required this.id,
    required this.name,
    this.companyId,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       updatedAt =
           updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String? companyId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  static final cashew = Product(id: 'cashew', name: 'Cashew');
  static final cocoa = Product(id: 'cocoa', name: 'Cocoa');
  static final sheaNuts = Product(id: 'shea_nuts', name: 'Shea Nuts');

  static final initialProducts = <Product>[cashew, cocoa, sheaNuts];

  Product copyWith({String? name, bool? isActive, DateTime? updatedAt}) {
    return Product(
      id: id,
      name: name ?? this.name,
      companyId: companyId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
