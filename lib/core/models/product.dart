// lib/core/models/product.dart

import 'product_variant.dart';

class Product {
  final String id;
  final String businessId;
  final String? categoryId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final String? barcode;
  final String? sku;
  final double costPrice;
  final bool trackInventory;
  final int stockQuantity;
  final bool isAvailable;
  final bool sendToKitchen;
  final bool isActive;
  // Local-only helper (populated from categories join or passed manually)
  final String category;
  // Variants — populated after a separate fetch; empty = no variants
  final List<ProductVariant> variants;

  const Product({
    required this.id,
    required this.businessId,
    this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.barcode,
    this.sku,
    this.costPrice = 0,
    this.trackInventory = true,
    this.stockQuantity = 0,
    this.isAvailable = true,
    this.isActive = true,
    this.sendToKitchen = true,
    this.category = '',
    this.variants = const [],
  });

  // ── Variant helpers ───────────────────────────────────────────────────────

  /// True when the product has at least one active variant
  bool get hasVariants => variants.any((v) => v.isActive);

  /// Active variants only — use this for display/picker
  List<ProductVariant> get activeVariants =>
      variants.where((v) => v.isActive).toList();

  /// Resolved price for a given variant (base + delta)
  double priceForVariant(ProductVariant variant) =>
      variant.resolvedPrice(price);

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory Product.fromMap(Map<String, dynamic> map) {
    final categoryMap = map['categories'] as Map<String, dynamic>?;
    return Product(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      categoryId: map['category_id'] as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      imageUrl: map['image_url'] as String?,
      barcode: map['barcode'] as String?,
      sku: map['sku'] as String?,
      trackInventory: map['track_inventory'] as bool? ?? true,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      isAvailable: map['is_available'] as bool? ?? true,
      isActive: map['is_active'] as bool? ?? true,
      sendToKitchen: map['send_to_kitchen'] as bool? ?? true,
      category: map['category_name'] as String? ??
          categoryMap?['name'] as String? ??
          '',
      // variants are never embedded in the products row; they're joined separately
      variants: const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'business_id': businessId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'price': price,
        'cost_price': costPrice,
        'image_url': imageUrl,
        'barcode': barcode,
        'sku': sku,
        'track_inventory': trackInventory,
        'stock_quantity': stockQuantity,
        'is_available': isAvailable,
        'is_active': isActive,
        'send_to_kitchen': sendToKitchen,
      };

  Product copyWith({
    String? name,
    double? price,
    double? costPrice,
    bool? isAvailable,
    int? stockQuantity,
    bool? sendToKitchen,
    List<ProductVariant>? variants,
  }) =>
      Product(
        id: id,
        businessId: businessId,
        categoryId: categoryId,
        name: name ?? this.name,
        description: description,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        imageUrl: imageUrl,
        barcode: barcode,
        sku: sku,
        trackInventory: trackInventory,
        sendToKitchen: sendToKitchen ?? this.sendToKitchen,
        stockQuantity: stockQuantity ?? this.stockQuantity,
        isAvailable: isAvailable ?? this.isAvailable,
        isActive: isActive,
        category: category,
        variants: variants ?? this.variants,
      );

  // ── Custom item support ───────────────────────────────────────────────────

  factory Product.custom({required String name, required double price}) {
    return Product(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      businessId: '',
      name: name,
      price: price,
      trackInventory: false,
      sendToKitchen: false,
      isAvailable: true,
      isActive: true,
      category: 'Miscellaneous',
    );
  }

  bool get isCustom => id.startsWith('custom_');
}