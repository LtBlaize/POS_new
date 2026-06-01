// lib/core/providers/cart_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';

// REPLACE
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  double orderDiscountAmount = 0;
  DiscountType orderDiscountType = DiscountType.fixed;
  OrderType orderType = OrderType.walkIn;

  void setOrderType(OrderType type) {
    orderType = type;
    state = [...state];
  }

  void applyOrderDiscount(double amount, DiscountType type) {
    orderDiscountAmount = amount;
    orderDiscountType = type;
    state = [...state]; // trigger rebuild
  }

  void applyItemDiscount(String productId, double amount, DiscountType type) {
    final index = state.indexWhere((i) => i.product.id == productId);
    if (index < 0) return;
    final updated = List<CartItem>.from(state);
    final item = state[index];
    updated[index] = CartItem(
      product: item.product,
      selectedVariant: item.selectedVariant,
      quantity: item.quantity,
      discountAmount: amount,
      discountType: type,
      costAtSale: item.costAtSale,
      notes: item.notes,
    );
    state = updated;
  }

  void setItemNotes(String productId, String? notes) {
    final index = state.indexWhere((i) => i.product.id == productId);
    if (index < 0) return;
    final updated = List<CartItem>.from(state);
    final item = state[index];
    updated[index] = CartItem(
      product: item.product,
      selectedVariant: item.selectedVariant,
      quantity: item.quantity,
      discountAmount: item.discountAmount,
      discountType: item.discountType,
      costAtSale: item.costAtSale,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
    );
    state = updated;
  }

  double get itemsTotal => state.fold(0, (sum, item) => sum + item.total);

  double get orderDiscountValue {
    if (orderDiscountType == DiscountType.percentage) {
      return itemsTotal * (orderDiscountAmount / 100);
    }
    return orderDiscountAmount;
  }

 double _tipAmount = 0;
  double get tipAmount => _tipAmount;

  void setTip(double amount) {
    _tipAmount = amount.clamp(0, double.infinity);
    state = [...state]; // trigger rebuild
  }

  double get grandTotal => (itemsTotal - orderDiscountValue + _tipAmount).clamp(0, double.infinity);

  void addProduct(Product product) {
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final current = state[index];
      if (product.trackInventory &&
          current.quantity >= product.stockQuantity) {
        return;
      }

      final updated = List<CartItem>.from(state);
      updated[index] = CartItem(
        product: current.product,
        selectedVariant: current.selectedVariant,
        quantity: current.quantity + 1,
        discountAmount: current.discountAmount,
        discountType: current.discountType,
        costAtSale: current.costAtSale,
        notes: current.notes,
      );
      state = updated;
    } else {
      state = [...state, CartItem(product: product)];
    }
  }

  void decrementProduct(String productId) {
    final index = state.indexWhere((item) => item.product.id == productId);
    if (index < 0) return;
    final current = state[index];
    if (current.quantity <= 1) {
      removeProduct(productId);
    } else {
      final updated = List<CartItem>.from(state);
      updated[index] = CartItem(
        product: current.product,
        selectedVariant: current.selectedVariant,
        quantity: current.quantity - 1,
        discountAmount: current.discountAmount,
        discountType: current.discountType,
        costAtSale: current.costAtSale,
        notes: current.notes,
      );
      state = updated;
    }
  }

  void removeProduct(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void clear() {
    orderDiscountAmount = 0;
    orderDiscountType = DiscountType.fixed;
    _tipAmount = 0;
    orderType = OrderType.walkIn;
    state = [];
  }

  void loadItems(List<CartItem> items) {
    orderDiscountAmount = 0;
    orderDiscountType = DiscountType.fixed;
    _tipAmount = 0;
    state = List.from(items);
  }

  double get total => grandTotal;
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);