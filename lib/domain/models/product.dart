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

  /// The products every company starts with, in the order the business expects
  /// to see them: Cashew, then Shea Nut, then Cocoa.
  ///
  /// This is deliberately NOT alphabetical. The ids and names are unchanged, so
  /// every existing product, record and test that refers to them keeps working;
  /// only the display order is defined here. Any product an admin adds later is
  /// not in this list and is shown after these three.
  static final initialProducts = <Product>[cashew, sheaNuts, cocoa];

  /// The position this product should be displayed at, or null when it is not
  /// one of the three products the business ships with.
  ///
  /// Used to guarantee the Cashew / Shea Nut / Cocoa order without relying on
  /// alphabetical sorting, which would put Cocoa before Shea.
  int? get displayRank {
    for (var index = 0; index < initialProducts.length; index++) {
      if (initialProducts[index].id == id) return index;
    }
    return null;
  }

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
