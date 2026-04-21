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
  final bool trackInventory;
  final int stockQuantity;
  final bool isAvailable;
  final bool isActive;
  // Local-only helper (populated from categories join or passed manually)
  final String category;

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
    this.trackInventory = false,
    this.stockQuantity = 0,
    this.isAvailable = true,
    this.isActive = true,
    this.category = '',
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    // categories is a joined object when using select('*, categories(name)')
    final categoryMap = map['categories'] as Map<String, dynamic>?;
    return Product(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      categoryId: map['category_id'] as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      barcode: map['barcode'] as String?,
      sku: map['sku'] as String?,
      trackInventory: map['track_inventory'] as bool? ?? false,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      isAvailable: map['is_available'] as bool? ?? true,
      isActive: map['is_active'] as bool? ?? true,
      category: categoryMap?['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'business_id': businessId,
    'category_id': categoryId,
    'name': name,
    'description': description,
    'price': price,
    'image_url': imageUrl,
    'barcode': barcode,
    'sku': sku,
    'track_inventory': trackInventory,
    'stock_quantity': stockQuantity,
    'is_available': isAvailable,
    'is_active': isActive,
  };

  Product copyWith({
    String? name,
    double? price,
    bool? isAvailable,
    int? stockQuantity,
  }) => Product(
    id: id,
    businessId: businessId,
    categoryId: categoryId,
    name: name ?? this.name,
    description: description,
    price: price ?? this.price,
    imageUrl: imageUrl,
    barcode: barcode,
    sku: sku,
    trackInventory: trackInventory,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    isAvailable: isAvailable ?? this.isAvailable,
    isActive: isActive,
    category: category,
  );
}