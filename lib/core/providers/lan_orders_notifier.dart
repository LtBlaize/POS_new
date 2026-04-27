// lib/core/providers/lan_orders_notifier.dart
//
// Riverpod notifier that owns the kitchen-side order list.
// Receives pushes from LanClientService and exposes them to KitchenScreen.
// KitchenScreen watches this instead of ordersStreamProvider (Supabase).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/lan_client_service.dart';
import '../../core/services/lan_status_queue.dart';
import '../../core/models/order.dart';
import '../../core/models/cart_item.dart'; // adjust path as needed
import '../../core/models/product.dart';   // adjust path as needed

// ── State ──────────────────────────────────────────────────────────────────

enum LanConnectionState { disconnected, connecting, connected, polling }

class KitchenState {
  final List<Order> orders;
  final LanConnectionState connection;
  final String? error;

  const KitchenState({
    this.orders = const [],
    this.connection = LanConnectionState.disconnected,
    this.error,
  });

  KitchenState copyWith({
    List<Order>? orders,
    LanConnectionState? connection,
    String? error,
  }) =>
      KitchenState(
        orders: orders ?? this.orders,
        connection: connection ?? this.connection,
        error: error,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────

final kitchenStateProvider =
    NotifierProvider<KitchenNotifier, KitchenState>(KitchenNotifier.new);

class KitchenNotifier extends Notifier<KitchenState> {
  @override
  KitchenState build() => const KitchenState();

  /// Call once when KitchenScreen mounts, passing in the businessId.
  void connect(String businessId) {
    state = state.copyWith(connection: LanConnectionState.connecting);
    ref.read(lanClientServiceProvider).connect(
      businessId: businessId,
      onOrders: _handleOrders,
      onEvent: _handleEvent,
    );
  }

  void _handleOrders(List<Map<String, dynamic>> raw) {
    final orders = raw.map(_parseOrder).toList();
    state = state.copyWith(
      orders: orders,
      connection: LanConnectionState.connected,
      error: null,
    );
  }

  void _handleEvent(Map<String, dynamic> event) {
    // Events are informational; the actual order list is refreshed via _handleOrders.
    // Could use this for sound/vibration alerts on 'order_placed'.
  }

  /// Called by _KitchenOrderCard to advance an order's status.
  Future<void> advanceStatus(String orderId, OrderStatus next) async {
    // Optimistic update — update local state immediately
    final updated = state.orders.map((o) {
      return o.id == orderId ? _copyWithStatus(o, next) : o;
    }).toList();
    state = state.copyWith(orders: updated);

    // Send to POS server
    final ok = await ref
        .read(lanClientServiceProvider)
        .patchStatus(orderId, next.value);

    if (!ok) {
      // POS unreachable — enqueue for retry
      ref.read(lanStatusQueueProvider).enqueue(orderId, next.value);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Order _parseOrder(Map<String, dynamic> m) {
    final items = (m['items'] as List).map((i) {
      final map = i as Map<String, dynamic>;
      return CartItem(
        product: Product(
          id: '',
          businessId: '',
          name: map['product_name'] as String,
          price: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
        ),
        quantity: map['quantity'] as int,
      );
    }).toList();

    return Order(
      id: m['id'] as String,
      businessId: '',
      orderNumber: m['order_number'] as int,
      tableId: m['table_id'] as String?,
      status: OrderStatusX.fromString(m['status'] as String),
      createdAt: DateTime.parse(m['created_at'] as String),
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
      items: items,
    );
  }

  Order _copyWithStatus(Order o, OrderStatus s) => o.copyWith(status: s);

}