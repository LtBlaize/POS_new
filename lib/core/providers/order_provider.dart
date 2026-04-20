// lib/core/providers/order_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../models/cart_item.dart';

class OrderNotifier extends StateNotifier<List<Order>> {
  OrderNotifier() : super([]);

  int _counter = 1;

  void placeOrder(List<CartItem> items) {
    if (items.isEmpty) return;
    final order = Order(
      id: 'ORD-${_counter.toString().padLeft(3, '0')}',
      items: List.from(items),
      status: 'pending',
    );
    _counter++;
    state = [...state, order];
  }

  void updateStatus(String orderId, String status) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          Order(id: o.id, items: o.items, status: status)
        else
          o,
    ];
  }

  void removeOrder(String orderId) {
    state = state.where((o) => o.id != orderId).toList();
  }

  List<Order> get pendingOrders =>
      state.where((o) => o.status == 'pending').toList();

  List<Order> get preparingOrders =>
      state.where((o) => o.status == 'preparing').toList();

  List<Order> get readyOrders =>
      state.where((o) => o.status == 'ready').toList();
}

final orderProvider =
    StateNotifierProvider<OrderNotifier, List<Order>>(
        (ref) => OrderNotifier());