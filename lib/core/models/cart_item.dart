import 'product.dart';

// REPLACE
enum DiscountType { percentage, fixed }

class CartItem {
  final Product product;
  int quantity;
  double discountAmount;
  DiscountType discountType;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.discountAmount = 0,
    this.discountType = DiscountType.fixed,
  });

  double get rawTotal => product.price * quantity;

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
      };

  factory CartItem.fromParkedMap(Map<String, dynamic> m) => CartItem(
        product: Product(
          id: m['product_id'] as String,
          businessId: m['product_business_id'] as String? ?? '',
          name: m['product_name'] as String,
          price: (m['product_price'] as num).toDouble(),
          category: m['product_category'] as String? ?? '',
          trackInventory: m['product_track_inventory'] as bool? ?? false,
          sendToKitchen: m['product_send_to_kitchen'] as bool? ?? false,
        ),
        quantity: m['quantity'] as int,
        discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
        discountType: DiscountType.values.firstWhere(
          (e) => e.name == m['discount_type'],
          orElse: () => DiscountType.fixed,
        ),
      );
}