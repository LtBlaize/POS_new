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
}