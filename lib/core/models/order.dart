import 'cart_item.dart';

class Order {
  final String id;
  final List<CartItem> items;
  final String status; // pending, preparing, ready

  Order({
    required this.id,
    required this.items,
    this.status = 'pending',
  });

  double get total =>
      items.fold(0, (sum, item) => sum + item.total);
}