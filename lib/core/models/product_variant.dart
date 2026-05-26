// lib/core/models/product_variant.dart

class ProductVariant {
  final String id;
  final String productId;
  final String name;        // e.g. "Small", "Red", "Vanilla"
  final String? optionType; // e.g. "size", "color", "flavor" — display-only label
  final double priceDelta;  // added to parent price; 0 = same price
  final String? sku;
  final String? barcode;
  final int stockQuantity;
  final bool isActive;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.optionType,
    this.priceDelta = 0,
    this.sku,
    this.barcode,
    this.stockQuantity = 0,
    this.isActive = true,
  });

  /// Resolved price = parent base price + delta
  double resolvedPrice(double basePrice) => basePrice + priceDelta;

  bool get isInStock => stockQuantity > 0;

  factory ProductVariant.fromMap(Map<String, dynamic> map) => ProductVariant(
        id: map['id'] as String,
        productId: map['product_id'] as String,
        name: map['name'] as String,
        optionType: map['option_type'] as String?,
        priceDelta: (map['price_delta'] as num?)?.toDouble() ?? 0,
        sku: map['sku'] as String?,
        barcode: map['barcode'] as String?,
        stockQuantity: map['stock_quantity'] as int? ?? 0,
        isActive: map['is_active'] as bool? ?? true,
      );

  /// For SQLite rows (booleans as int)
  factory ProductVariant.fromLocalRow(Map<String, dynamic> row) =>
      ProductVariant(
        id: row['id'] as String,
        productId: row['product_id'] as String,
        name: row['name'] as String,
        optionType: row['option_type'] as String?,
        priceDelta: (row['price_delta'] as num?)?.toDouble() ?? 0,
        sku: row['sku'] as String?,
        barcode: row['barcode'] as String?,
        stockQuantity: row['stock_quantity'] as int? ?? 0,
        isActive: (row['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'name': name,
        'option_type': optionType,
        'price_delta': priceDelta,
        'sku': sku,
        'barcode': barcode,
        'stock_quantity': stockQuantity,
        'is_active': isActive,
      };

  ProductVariant copyWith({
    String? name,
    String? optionType,
    double? priceDelta,
    String? sku,
    String? barcode,
    int? stockQuantity,
    bool? isActive,
  }) =>
      ProductVariant(
        id: id,
        productId: productId,
        name: name ?? this.name,
        optionType: optionType ?? this.optionType,
        priceDelta: priceDelta ?? this.priceDelta,
        sku: sku ?? this.sku,
        barcode: barcode ?? this.barcode,
        stockQuantity: stockQuantity ?? this.stockQuantity,
        isActive: isActive ?? this.isActive,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductVariant &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}