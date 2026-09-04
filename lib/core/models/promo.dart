// lib/core/models/promo.dart

enum PromoType { bundle, buyXGetY }

extension PromoTypeX on PromoType {
  String get value => switch (this) {
        PromoType.bundle => 'bundle',
        PromoType.buyXGetY => 'buy_x_get_y',
      };
  static PromoType fromString(String v) => switch (v) {
        'buy_x_get_y' => PromoType.buyXGetY,
        _ => PromoType.bundle,
      };
}

enum PromoItemRole { bundle, buy, get }

extension PromoItemRoleX on PromoItemRole {
  String get value => switch (this) {
        PromoItemRole.bundle => 'bundle',
        PromoItemRole.buy => 'buy',
        PromoItemRole.get => 'get',
      };
  static PromoItemRole fromString(String v) => switch (v) {
        'buy' => PromoItemRole.buy,
        'get' => PromoItemRole.get,
        _ => PromoItemRole.bundle,
      };
}

class PromoItem {
  final String id;
  final String promoId;
  final String productId;
  final String? variantId;
  final int quantity;
  final PromoItemRole role;

  // Denormalized display fields — populated by a join when fetching,
  // not persisted on this table. Keeps the picker/list UI from needing
  // a second round trip per promo.
  final String? productName;
  final String? variantName;
  final double? productPrice;
  final bool? productTrackInventory;
  final bool? productSendToKitchen;

  const PromoItem({
    required this.id,
    required this.promoId,
    required this.productId,
    this.variantId,
    required this.quantity,
    this.role = PromoItemRole.bundle,
    this.productName,
    this.variantName,
    this.productPrice,
    this.productTrackInventory,
    this.productSendToKitchen,
  });

  factory PromoItem.fromMap(Map<String, dynamic> map) => PromoItem(
        id: map['id'] as String,
        promoId: map['promo_id'] as String,
        productId: map['product_id'] as String,
        variantId: map['variant_id'] as String?,
        quantity: map['quantity'] as int,
        role: PromoItemRoleX.fromString(map['role'] as String? ?? 'bundle'),
        productName: map['product_name'] as String?,
        variantName: map['variant_name'] as String?,
        productPrice: (map['product_price'] as num?)?.toDouble(),
        productTrackInventory: map['product_track_inventory'] as bool?,
        productSendToKitchen: map['product_send_to_kitchen'] as bool?,
      );

  Map<String, dynamic> toMap() => {
        'promo_id': promoId,
        'product_id': productId,
        'variant_id': variantId,
        'quantity': quantity,
        'role': role.value,
      };
}

class Promo {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final String? imageUrl;
  final PromoType promoType;
  final double? bundlePrice;
  final int? buyQuantity;
  final int? getQuantity;
  final double? getDiscountPercent;
  final bool isActive;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<PromoItem> items;

  const Promo({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    this.imageUrl,
    required this.promoType,
    this.bundlePrice,
    this.buyQuantity,
    this.getQuantity,
    this.getDiscountPercent,
    this.isActive = true,
    this.startDate,
    this.endDate,
    this.items = const [],
  });

  // ── Availability ─────────────────────────────────────────────────────────

  bool get isWithinDateRange {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  bool get isPurchasable => isActive && isWithinDateRange;

  List<PromoItem> get bundleItems =>
      items.where((i) => i.role == PromoItemRole.bundle).toList();
  List<PromoItem> get buyItems =>
      items.where((i) => i.role == PromoItemRole.buy).toList();
  List<PromoItem> get getItems =>
      items.where((i) => i.role == PromoItemRole.get).toList();

  // ── Pricing ──────────────────────────────────────────────────────────────

  /// Sum of each component's normal price × quantity — used to show savings.
  double get originalTotal {
    switch (promoType) {
      case PromoType.bundle:
        return bundleItems.fold<double>(
          0,
          (sum, i) => sum + (i.productPrice ?? 0) * i.quantity,
        );
      case PromoType.buyXGetY:
        final buyTotal = buyItems.fold<double>(
          0,
          (sum, i) => sum + (i.productPrice ?? 0) * i.quantity * (buyQuantity ?? 1),
        );
        final getTotal = getItems.fold<double>(
          0,
          (sum, i) => sum + (i.productPrice ?? 0) * i.quantity * (getQuantity ?? 1),
        );
        return buyTotal + getTotal;
    }
  }

  /// What the customer actually pays for one unit of this promo.
  double get effectivePrice {
    switch (promoType) {
      case PromoType.bundle:
        return bundlePrice ?? originalTotal;
      case PromoType.buyXGetY:
        final buyTotal = buyItems.fold<double>(
          0,
          (sum, i) => sum + (i.productPrice ?? 0) * i.quantity * (buyQuantity ?? 1),
        );
        final getTotal = getItems.fold<double>(
          0,
          (sum, i) => sum + (i.productPrice ?? 0) * i.quantity * (getQuantity ?? 1),
        );
        final discount = (getDiscountPercent ?? 100) / 100;
        return buyTotal + (getTotal * (1 - discount));
    }
  }

  double get savings => (originalTotal - effectivePrice).clamp(0, double.infinity);

  factory Promo.fromMap(Map<String, dynamic> map, {List<PromoItem> items = const []}) =>
      Promo(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        imageUrl: map['image_url'] as String?,
        promoType: PromoTypeX.fromString(map['promo_type'] as String),
        bundlePrice: (map['bundle_price'] as num?)?.toDouble(),
        buyQuantity: map['buy_quantity'] as int?,
        getQuantity: map['get_quantity'] as int?,
        getDiscountPercent: (map['get_discount_percent'] as num?)?.toDouble(),
        isActive: map['is_active'] as bool? ?? true,
        startDate: map['start_date'] != null ? DateTime.parse(map['start_date'] as String) : null,
        endDate: map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null,
        items: items,
      );

  Map<String, dynamic> toMap() => {
        'business_id': businessId,
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'promo_type': promoType.value,
        'bundle_price': bundlePrice,
        'buy_quantity': buyQuantity,
        'get_quantity': getQuantity,
        'get_discount_percent': getDiscountPercent,
        'is_active': isActive,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
      };

  Promo copyWith({
    String? name,
    String? description,
    String? imageUrl,
    double? bundlePrice,
    bool? isActive,
    DateTime? startDate,
    DateTime? endDate,
    List<PromoItem>? items,
  }) =>
      Promo(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        promoType: promoType,
        bundlePrice: bundlePrice ?? this.bundlePrice,
        buyQuantity: buyQuantity,
        getQuantity: getQuantity,
        getDiscountPercent: getDiscountPercent,
        isActive: isActive ?? this.isActive,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        items: items ?? this.items,
      );
}

// ── Cart-side representation ────────────────────────────────────────────────
//
// One PromoComponent = one underlying product/variant line that a promo
// expands into at checkout time, for inventory deduction and kitchen/receipt
// display. Lives on CartItem, not on Promo — see cart_item.dart patch.

class PromoComponent {
  final String promoId;
  final String productId;
  final String? variantId;
  final String productName;
  final String? variantName;
  final int quantity; // per one unit of the promo in the cart
  final bool trackInventory;
  final bool sendToKitchen;

  const PromoComponent({
    required this.promoId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    required this.quantity,
    required this.trackInventory,
    required this.sendToKitchen,
  });

  factory PromoComponent.fromParkedMap(Map<String, dynamic> m) => PromoComponent(
        promoId: m['promo_id'] as String,
        productId: m['product_id'] as String,
        variantId: m['variant_id'] as String?,
        productName: m['product_name'] as String,
        variantName: m['variant_name'] as String?,
        quantity: m['quantity'] as int,
        trackInventory: m['track_inventory'] as bool? ?? false,
        sendToKitchen: m['send_to_kitchen'] as bool? ?? false,
      );

  Map<String, dynamic> toParkedMap() => {
        'promo_id': promoId,
        'product_id': productId,
        'variant_id': variantId,
        'product_name': productName,
        'variant_name': variantName,
        'quantity': quantity,
        'track_inventory': trackInventory,
        'send_to_kitchen': sendToKitchen,
      };
}