// lib/core/providers/lan_orders_notifier.dart
//
// Riverpod notifier that owns the kitchen-side order list.
// Receives pushes from LanClientService and exposes them to KitchenScreen.
// KitchenScreen watches this instead of ordersStreamProvider (Supabase).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/lan_client_service.dart';
import '../../core/services/lan_status_queue.dart';
import '../../core/services/local_db_service.dart';
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
  String? _businessId;

  @override
  KitchenState build() => const KitchenState();

  /// Call once when KitchenScreen mounts, passing in the businessId.
  Future<void> connect(String businessId) async {
    _businessId = businessId;
    state = state.copyWith(connection: LanConnectionState.connecting);

    // Hydrate from local cache immediately so a kitchen tablet reboot
    // mid-outage shows in-progress orders instead of an empty screen
    // while LAN/WS is still reconnecting.
    try {
      final cached = await ref.read(localDbServiceProvider).getOrders(businessId);
      final active = cached
          .where((o) =>
              o.status == OrderStatus.pending ||
              o.status == OrderStatus.preparing ||
              o.status == OrderStatus.ready)
          .toList();
      if (active.isNotEmpty) {
        state = state.copyWith(orders: active);
      }
    } catch (e) {
      debugPrint('[Kitchen] Local cache hydrate failed: $e');
    }

    ref.read(lanClientServiceProvider).connect(
      businessId: businessId,
      onOrders: _handleOrders,
      onEvent: _handleEvent,
    );
  }

  void _handleOrders(List<Map<String, dynamic>> raw) {
    final businessId = _businessId ?? '';
    final orders = raw.map((m) => _parseOrder(m, businessId)).toList();
    state = state.copyWith(
      orders: orders,
      connection: LanConnectionState.connected,
      error: null,
    );

    // Mirror the server's active-order snapshot locally so it survives
    // a reboot. Fire-and-forget — UI state above is already updated.
    if (businessId.isNotEmpty) {
      final local = ref.read(localDbServiceProvider);
      local.upsertOrders(orders);
      local.pruneKitchenOrders(businessId, orders.map((o) => o.id).toList());
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    // Events are informational; the actual order list is refreshed via _handleOrders.
    // Could use this for sound/vibration alerts on 'order_placed'.
  }

  /// Called by the kitchen card to advance one round of an order.
  Future<void> advanceRound(String orderId, int round, String next) async {
    final updated = state.orders.map((o) {
      if (o.id != orderId) return o;
      final items = [
        for (final i in o.items)
          (i.round == round && i.kitchenStatus != 'served')
              ? i.withKitchenStatus(next)
              : i,
      ];
      return o.copyWith(
        items: items,
        status: OrderStatusX.fromString(
            deriveOrderStatus(items.map((i) => i.kitchenStatus))),
      );
    }).toList();
    state = state.copyWith(orders: updated);

    final ok = await ref
        .read(lanClientServiceProvider)
        .patchStatus(orderId, next, round: round);
    if (!ok) {
      ref.read(lanStatusQueueProvider).enqueue(orderId, next, round: round);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Order _parseOrder(Map<String, dynamic> m, String businessId) {
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
        round: (map['round'] as int?) ?? 1,
        kitchenStatus: (map['kitchen_status'] as String?) ?? 'pending',        
      );
    }).toList();

    return Order(
      id: m['id'] as String,
      businessId: businessId,
      orderNumber: m['order_number'] as int,
      tableId: m['table_id'] as String?,
      orderType: OrderTypeX.fromString(m['order_type'] as String? ?? 'walk_in'),
      customerName: m['customer_name'] as String?,
      status: OrderStatusX.fromString(m['status'] as String),
      createdAt: DateTime.parse(m['created_at'] as String),
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
      items: items,
    );
  }


}