// lib/core/providers/cart_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addProduct(Product product) {
    if (product.trackInventory && product.stockQuantity <= 0) return;

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
        quantity: current.quantity + 1,
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
      updated[index] =
          CartItem(product: current.product, quantity: current.quantity - 1);
      state = updated;
    }
  }

  void removeProduct(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void clear() => state = [];

  double get total => state.fold(0, (sum, item) => sum + item.total);
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);