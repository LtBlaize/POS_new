
import 'product.dart';
import 'product_variant.dart';
import 'promo.dart';

// REPLACE
enum DiscountType { percentage, fixed }

class CartItem {
  final Product product;
  final ProductVariant? selectedVariant;
  int quantity;
  double discountAmount;
  DiscountType discountType;
  final double costAtSale;
  final String? notes;
  // Non-null only for a promo/bundle line. Each entry is one underlying
  // product this promo expands into — used for inventory deduction and
  // receipt/kitchen reconstruction. Null for every ordinary cart item.
  final List<PromoComponent>? promoComponents;
  final String? promoId;

  CartItem({
    required this.product,
    this.selectedVariant,
    this.quantity = 1,
    this.discountAmount = 0,
    this.discountType = DiscountType.fixed,
    double? costAtSale,
    this.notes,
    this.promoComponents,
    this.promoId,
  }) : costAtSale = costAtSale ??
            (selectedVariant?.costPrice != null && selectedVariant!.costPrice > 0
                ? selectedVariant.costPrice
                : product.costPrice);

  bool get isPromo => promoComponents != null;

  /// Groups raw order_item-like rows [T] into CartItems. Rows sharing a
  /// non-null promo-group id become one promo CartItem (header + its
  /// components); rows with no group id are standalone items untouched.
  ///
  /// Callers supply how to read the group id off a row, how to recognize
  /// the header row within a group, and how to build a CartItem / a
  /// PromoComponent from a row — since row shape (Supabase join, local
  /// SQLite, kitchen's nested map) differs per caller.
  static List<CartItem> groupOrderItemRows<T>(
    List<T> rows, {
    required String? Function(T row) promoGroupId,
    required bool Function(T row) isHeaderRow,
    required CartItem Function(T headerOrStandaloneRow) buildItem,
    required PromoComponent Function(T componentRow) buildComponent,
  }) {
    final result = <CartItem>[];
    final groups = <String, List<T>>{};

    for (final row in rows) {
      final gid = promoGroupId(row);
      if (gid == null) {
        result.add(buildItem(row));
      } else {
        groups.putIfAbsent(gid, () => []).add(row);
      }
    }

    for (final rowsInGroup in groups.values) {
      final headerRow =
          rowsInGroup.firstWhere(isHeaderRow, orElse: () => rowsInGroup.first);
      final componentRows =
          rowsInGroup.where((r) => !isHeaderRow(r)).toList();
      final header = buildItem(headerRow);
      result.add(CartItem(
        product: header.product,
        quantity: header.quantity,
        discountAmount: header.discountAmount,
        discountType: header.discountType,
        costAtSale: header.costAtSale,
        notes: header.notes,
        promoId: header.promoId,
        promoComponents: componentRows.map(buildComponent).toList(),
      ));
    }
    return result;
  }
  double get effectivePrice => selectedVariant != null
      ? selectedVariant!.resolvedPrice(product.price)
      : product.price;

  double get rawTotal => effectivePrice * quantity;

  double get discountValue => discountType == DiscountType.percentage
      ? rawTotal * (discountAmount / 100)
      : discountAmount;

  double get total => (rawTotal - discountValue).clamp(0, double.infinity);

 Map<String, dynamic> toParkedMap() => {
        'product_id': product.id,
        'product_business_id': product.businessId,
        'product_name': product.name,
        'product_price': product.price,
        'product_category': product.category,
        'product_track_inventory': product.trackInventory,
        'product_send_to_kitchen': product.sendToKitchen,
        'quantity': quantity,
        'discount_amount': discountAmount,
        'discount_type': discountType.name,
        'variant_id': selectedVariant?.id,
        'variant_name': selectedVariant?.name,
        'variant_price_delta': selectedVariant?.priceDelta,
        'variant_cost_price': selectedVariant?.costPrice,
        'cost_at_sale': costAtSale,
        'notes': notes,
        'promo_id': promoId,
        'promo_components': promoComponents?.map((c) => c.toParkedMap()).toList(),
      };

  factory CartItem.fromParkedMap(Map<String, dynamic> m) {
    final variantId = m['variant_id'] as String?;
    final selectedVariant = variantId != null
        ? ProductVariant(
            id: variantId,
            productId: m['product_id'] as String,
            name: m['variant_name'] as String? ?? '',
            priceDelta: (m['variant_price_delta'] as num?)?.toDouble() ?? 0,
            costPrice: (m['variant_cost_price'] as num?)?.toDouble() ?? 0,
          )
        : null;

    return CartItem(
      product: Product(
        id: m['product_id'] as String,
        businessId: m['product_business_id'] as String? ?? '',
        name: m['product_name'] as String,
        price: (m['product_price'] as num).toDouble(),
        category: m['product_category'] as String? ?? '',
        trackInventory: m['product_track_inventory'] as bool? ?? false,
        sendToKitchen: m['product_send_to_kitchen'] as bool? ?? false,
      ),
      selectedVariant: selectedVariant,
      quantity: m['quantity'] as int,
      discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
      discountType: DiscountType.values.firstWhere(
        (e) => e.name == m['discount_type'],
        orElse: () => DiscountType.fixed,
      ),
      costAtSale: (m['cost_at_sale'] as num?)?.toDouble() ?? 0,
      notes: m['notes'] as String?,
      promoId: m['promo_id'] as String?,
      promoComponents: (m['promo_components'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map(PromoComponent.fromParkedMap)
          .toList(),
    );
  }
}