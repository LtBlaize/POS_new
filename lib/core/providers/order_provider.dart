import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../../features/auth/auth_provider.dart';
import 'product_provider.dart';

// ── Live orders stream for the current business ───────────────────────────────

final ordersStreamProvider = StreamProvider<List<Order>>((ref) async* {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) { yield []; return; }

  final client = ref.watch(supabaseClientProvider);

  yield* client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('business_id', profile!.businessId!)
      .order('created_at', ascending: false)
      .map((rows) => rows
          .map((m) => Order.fromMap(m))
          .toList());
});

// ── Filtered views ────────────────────────────────────────────────────────────

final pendingOrdersProvider = Provider<List<Order>>((ref) {
  final orders = ref.watch(ordersStreamProvider).asData?.value ?? [];
  return orders
      .where((o) => o.status == OrderStatus.pending || o.status == OrderStatus.preparing)
      .toList();
});

final completedOrdersProvider = Provider<List<Order>>((ref) {
  final orders = ref.watch(ordersStreamProvider).asData?.value ?? [];
  return orders.where((o) => o.status == OrderStatus.completed).toList();
});

// ── OrderService: place + manage orders ──────────────────────────────────────

final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService(
    client: ref.watch(supabaseClientProvider),
    ref: ref,
  );
});

class OrderService {
  final SupabaseClient _client;
  final Ref _ref;
  OrderService({required SupabaseClient client, required Ref ref})
      : _client = client,
        _ref = ref;

  /// Places a new order + writes order_items. Returns the created Order.
  Future<Order> placeOrder({
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    double taxRate = 0.0,
    double discountAmount = 0.0,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount;

    // 1. Insert order row
    final orderRow = await _client
        .from('orders')
        .insert({
          'business_id': businessId,
          'table_id': tableId,
          'cashier_id': _client.auth.currentUser?.id,
          'order_type': tableId != null ? 'dine_in' : 'walk_in',
          'status': 'pending',
          'subtotal': subtotal,
          'tax_amount': taxAmount,
          'discount_amount': discountAmount,
          'total_amount': totalAmount,
          'notes': notes,
        })
        .select()
        .single();

    final orderId = orderRow['id'] as String;

    // 2. Insert order_items
    final orderItems = items
        .map((item) => {
              'order_id': orderId,
              'product_id': item.product.id,
              'product_name': item.product.name,
              'unit_price': item.product.price,
              'quantity': item.quantity,
              'subtotal': item.total,
            })
        .toList();

    await _client.from('order_items').insert(orderItems);

    // 3. Deduct inventory for tracked products
    try {
      final inventoryService = _ref.read(inventoryServiceProvider);
      for (final item in items) {
        if (item.product.trackInventory) {
          await inventoryService.adjustStock(
            businessId: businessId,
            productId: item.product.id,
            quantityChange: -item.quantity,
            quantityBefore: item.product.stockQuantity,
            action: 'sale',
          );
        }
      }
      // Refresh products so stock counts update in the UI
      _ref.invalidate(productListProvider);
    } catch (e) {
      debugPrint('Inventory deduction error (non-fatal): $e');
    }

    return Order.fromMap(orderRow, items: items);
  }

  /// Update order status (pending → preparing → ready → completed)
  Future<void> updateStatus(String orderId, OrderStatus status) async {
    final update = <String, dynamic>{
      'status': status.value,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status == OrderStatus.completed) {
      update['paid_at'] = DateTime.now().toIso8601String();
    }
    await _client.from('orders').update(update).eq('id', orderId);
  }

  /// Record payment details on an order
  Future<void> processPayment({
    required String orderId,
    required PaymentMethod method,
    required double amountTendered,
    required double changeAmount,
  }) async {
    await _client.from('orders').update({
      'payment_method': method.value,
      'amount_tendered': amountTendered,
      'change_amount': changeAmount,
      'status': OrderStatus.completed.value,
      'paid_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Fetch full order with its items (for receipt/detail view)
  Future<Order> fetchOrderWithItems(String orderId) async {
    final orderRow = await _client
        .from('orders')
        .select()
        .eq('id', orderId)
        .single();

    final itemRows = await _client
        .from('order_items')
        .select('*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active)')
        .eq('order_id', orderId);

    final cartItems = (itemRows as List).map((row) {
      final pMap = row['products'] as Map<String, dynamic>? ?? {};
      final product = Product.fromMap({
        ...pMap,
        'category': '',
        'business_id': pMap['business_id'] ?? '',
      });
      return CartItem(product: product, quantity: row['quantity'] as int);
    }).toList();

    return Order.fromMap(orderRow, items: cartItems);
  }
}
// ── LEGACY: kept for backward compat during migration ─────────────────────────
// Remove once orders_screen and kitchen_screen are fully updated below.
class OrderNotifier extends StateNotifier<List<Order>> {
  OrderNotifier() : super([]);
  void updateStatus(String orderId, String status) {}
  void removeOrder(String orderId) {}
}
final orderProvider = StateNotifierProvider<OrderNotifier, List<Order>>(
  (ref) => OrderNotifier(),
);