// lib/core/services/parked_order_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/cart_item.dart';
import '../models/parked_order.dart';
import '../providers/cart_provider.dart';
import 'local_db_service.dart';
import 'lan_server_service.dart';

final parkedOrderServiceProvider =
    Provider<ParkedOrderService>((ref) => ParkedOrderService(ref));
class ParkedOrderService {
  final Ref ref;

  ParkedOrderService(this.ref);
}
// ── State ─────────────────────────────────────────────────────────────────────

class ParkedOrderState {
  final List<ParkedOrder> orders;
  final bool loading;

  const ParkedOrderState({this.orders = const [], this.loading = false});

  ParkedOrderState copyWith({List<ParkedOrder>? orders, bool? loading}) =>
      ParkedOrderState(
        orders: orders ?? this.orders,
        loading: loading ?? this.loading,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ParkedOrderNotifier extends StateNotifier<ParkedOrderState> {
  final Ref _ref;
  ParkedOrderNotifier(this._ref) : super(const ParkedOrderState()) {
    _load();
  }

  LocalDbService get _local => _ref.read(localDbServiceProvider);

  Future<void> _load() async {
    state = state.copyWith(loading: true);
    try {
      final rows = await _local.getParkedOrders();
      state = ParkedOrderState(
        orders: rows.map(ParkedOrder.fromMap).toList(),
        loading: false,
      );
    } catch (e) {
      debugPrint('[ParkedOrders] Load failed: $e');
      state = state.copyWith(loading: false);
    }
  }

  /// Serializes the current cart and saves it as a parked order.
  Future<void> parkCart({
    required String businessId,
    required String label,
    required List<CartItem> items,
    required double orderDiscountAmount,
    required DiscountType orderDiscountType,
    required double tipAmount,
  }) async {
    final id = const Uuid().v4();
    final parked = ParkedOrder(
      id: id,
      businessId: businessId,
      label: label.trim().isEmpty ? 'Order ${state.orders.length + 1}' : label.trim(),
      items: items,
      orderDiscountAmount: orderDiscountAmount,
      orderDiscountType: orderDiscountType,
      tipAmount: tipAmount,
      parkedAt: DateTime.now(),
    );

    await _local.insertParkedOrder(parked.toMap());

    state = state.copyWith(orders: [...state.orders, parked]);

    // Broadcast to LAN clients so other POS devices see the parked order
    _broadcastEvent('parked_order_added', parked.toMap());

    debugPrint('[ParkedOrders] Parked: ${parked.label}');
  }

  /// Restores a parked order into the cart and removes it from the parked list.
  Future<void> restoreToCart(String parkedOrderId) async {
    final index = state.orders.indexWhere((o) => o.id == parkedOrderId);
    if (index < 0) return;

    final parked = state.orders[index];
    final cartNotifier = _ref.read(cartProvider.notifier);

    cartNotifier.clear();
    for (final item in parked.items) {
      for (var i = 0; i < item.quantity; i++) {
        cartNotifier.addProduct(item.product);
      }
    }
    cartNotifier.applyOrderDiscount(
        parked.orderDiscountAmount, parked.orderDiscountType);
    cartNotifier.setTip(parked.tipAmount);

    await _deleteParked(parkedOrderId);
  }

  Future<void> deleteParked(String parkedOrderId) =>
      _deleteParked(parkedOrderId);

  Future<void> _deleteParked(String parkedOrderId) async {
    await _local.deleteParkedOrder(parkedOrderId);
    state = state.copyWith(
      orders: state.orders.where((o) => o.id != parkedOrderId).toList(),
    );
    _broadcastEvent('parked_order_removed', {'id': parkedOrderId});
  }

  /// Called when a LAN broadcast arrives from another device.
  void handleLanEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    if (type == 'parked_order_added') {
      try {
        final parked = ParkedOrder.fromMap(payload);
        if (!state.orders.any((o) => o.id == parked.id)) {
          state = state.copyWith(orders: [...state.orders, parked]);
        }
      } catch (e) {
        debugPrint('[ParkedOrders] LAN add parse error: $e');
      }
    } else if (type == 'parked_order_removed') {
      final id = payload['id'] as String?;
      if (id != null) {
        state = state.copyWith(
          orders: state.orders.where((o) => o.id != id).toList(),
        );
      }
    }
  }

  void _broadcastEvent(String type, Map<String, dynamic> payload) {
    try {
      final server = _ref.read(lanServerServiceProvider);
      if (server.isRunning) {
        server.broadcastParkedOrderEvent(type, payload);
      }
    } catch (e) {
      debugPrint('[ParkedOrders] LAN broadcast failed: $e');
    }
  }
}

final parkedOrderProvider =
    StateNotifierProvider<ParkedOrderNotifier, ParkedOrderState>(
  (ref) => ParkedOrderNotifier(ref),
);