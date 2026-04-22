// lib/core/providers/cart_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../../features/auth/auth_provider.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addProduct(Product product) {
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final updated = List<CartItem>.from(state);
      updated[index] = CartItem(
        product: updated[index].product,
        quantity: updated[index].quantity + 1,
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

// FIX: scope cart to the authenticated user ID.
// Each unique userId gets its own CartNotifier instance, so when the user
// logs out and a different account logs in, they get a completely fresh cart.
final _cartFamilyProvider =
    StateNotifierProvider.family<CartNotifier, List<CartItem>, String?>(
  (ref, userId) => CartNotifier(),
);

// Use this everywhere in the app — it auto-resolves the current user's cart.
final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  // Watching authStateProvider means this re-runs on login/logout,
  // handing back a different CartNotifier for each userId.
  final userId = ref.watch(authStateProvider).asData?.value?.id;
  return ref.read(_cartFamilyProvider(userId).notifier);
});