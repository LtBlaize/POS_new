// lib/core/models/parked_order.dart
import 'dart:convert';
import 'cart_item.dart';
import 'product.dart';

class ParkedOrder {
  final String id;
  final String businessId;
  final String label;
  final List<CartItem> items;
  final double orderDiscountAmount;
  final DiscountType orderDiscountType;
  final double tipAmount;
  final DateTime parkedAt;

  const ParkedOrder({
    required this.id,
    required this.businessId,
    required this.label,
    required this.items,
    this.orderDiscountAmount = 0,
    this.orderDiscountType = DiscountType.fixed,
    this.tipAmount = 0,
    required this.parkedAt,
  });

  double get total {
    final itemsTotal = items.fold(0.0, (s, i) => s + i.total);
    final discount = orderDiscountType == DiscountType.percentage
        ? itemsTotal * (orderDiscountAmount / 100)
        : orderDiscountAmount;
    return (itemsTotal - discount + tipAmount).clamp(0, double.infinity);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'label': label,
        'items': jsonEncode(items.map((i) => _itemToMap(i)).toList()),
        'order_discount_amount': orderDiscountAmount,
        'order_discount_type': orderDiscountType.name,
        'tip_amount': tipAmount,
        'parked_at': parkedAt.toIso8601String(),
      };

  factory ParkedOrder.fromMap(Map<String, dynamic> map) => ParkedOrder(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        label: map['label'] as String,
        items: (jsonDecode(map['items'] as String) as List)
            .map((e) => _itemFromMap(e as Map<String, dynamic>))
            .toList(),
        orderDiscountAmount:
            (map['order_discount_amount'] as num?)?.toDouble() ?? 0,
        orderDiscountType: DiscountType.values.firstWhere(
          (e) => e.name == map['order_discount_type'],
          orElse: () => DiscountType.fixed,
        ),
        tipAmount: (map['tip_amount'] as num?)?.toDouble() ?? 0,
        parkedAt: DateTime.parse(map['parked_at'] as String),
      );

  static Map<String, dynamic> _itemToMap(CartItem item) => {
        'product_id': item.product.id,
        'product_business_id': item.product.businessId,
        'product_name': item.product.name,
        'product_price': item.product.price,
        'product_category': item.product.category,
        'product_track_inventory': item.product.trackInventory,
        'product_send_to_kitchen': item.product.sendToKitchen,
        'product_is_custom': item.product.isCustom,
        'quantity': item.quantity,
        'discount_amount': item.discountAmount,
        'discount_type': item.discountType.name,
      };

  static CartItem _itemFromMap(Map<String, dynamic> m) => CartItem(
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