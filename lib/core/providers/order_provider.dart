// lib/core/providers/order_provider.dart
//
// Offline-first orders:
//   Online  → place via Supabase, stream live updates, cache locally
//   Offline → generate local UUID, store in SQLite, queue for Supabase sync
//
// ordersStreamProvider always yields data (live stream or cached snapshot).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';
import 'product_provider.dart';

// ── Live / cached order stream ────────────────────────────────────────────────

final ordersStreamProvider = StreamProvider<List<Order>>((ref) async* {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) {
    yield [];
    return;
  }

  final businessId = profile!.businessId!;
  final local = ref.read(localDbServiceProvider);

  // Always seed from local cache first
  final cached = await local.getOrders(businessId);
  if (cached.isNotEmpty) yield cached;

  // If offline, wait until connectivity is restored before hitting Supabase
  if (!ref.read(isOnlineProvider)) {
    final completer = Completer<void>();
    final sub = ref.listen<bool>(isOnlineProvider, (_, next) {
      if (next && !completer.isCompleted) completer.complete();
    });
    await completer.future;
    sub.close();

    // Yield a fresh cache snapshot right before going online
    final refreshed = await local.getOrders(businessId);
    yield refreshed;
  }

  // Online: stream from Supabase and keep cache warm
  final client = ref.watch(supabaseClientProvider);

  yield* client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('business_id', businessId)
      .order('created_at', ascending: false)
      .asyncMap((rows) async {
        final orders = await Future.wait(rows.map((row) async {
          final orderId = row['id'] as String;
          final itemRows = await client
              .from('order_items')
              .select(
                  '*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active)')
              .eq('order_id', orderId);

          final cartItems = (itemRows as List).map((item) {
            final pMap =
                item['products'] as Map<String, dynamic>? ?? {};
            final product = Product.fromMap({
              ...pMap,
              'category': '',
              'business_id': pMap['business_id'] ?? '',
            });
            return CartItem(product: product, quantity: item['quantity'] as int);
          }).toList();

          return Order.fromMap(row, items: cartItems);
        }));
        

        // Write-through to local cache
        await local.upsertOrders(orders);
        return orders;
      });
});

// ── Filtered views ────────────────────────────────────────────────────────────

final pendingOrdersProvider = Provider<List<Order>>((ref) {
  final orders = ref.watch(ordersStreamProvider).asData?.value ?? [];
  return orders
      .where((o) =>
          o.status == OrderStatus.pending ||
          o.status == OrderStatus.preparing)
      .toList();
});

final completedOrdersProvider = Provider<List<Order>>((ref) {
  final orders = ref.watch(ordersStreamProvider).asData?.value ?? [];
  return orders.where((o) => o.status == OrderStatus.completed).toList();
});

// ── OrderService ──────────────────────────────────────────────────────────────

final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService(
    client: ref.watch(supabaseClientProvider),
    local: ref.read(localDbServiceProvider),
    syncQueue: ref.read(syncQueueServiceProvider),
    ref: ref,
  );
});

class OrderService {
  final SupabaseClient _client;
  final LocalDbService _local;
  final SyncQueueService _syncQueue;
  final Ref _ref;

  OrderService({
    required SupabaseClient client,
    required LocalDbService local,
    required SyncQueueService syncQueue,
    required Ref ref,
  })  : _client = client,
        _local = local,
        _syncQueue = syncQueue,
        _ref = ref;

  bool get _isOnline => _ref.read(isOnlineProvider);

  // ── Place order ─────────────────────────────────────────────────────────────

  Future<Order> placeOrder({
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    double taxRate = 0.0,
    double discountAmount = 0.0,
  }) async {
    if (_isOnline) {
      return _placeOnline(
        businessId: businessId,
        items: items,
        tableId: tableId,
        notes: notes,
        taxRate: taxRate,
        discountAmount: discountAmount,
      );
    } else {
      return _placeOffline(
        businessId: businessId,
        items: items,
        tableId: tableId,
        notes: notes,
        taxRate: taxRate,
        discountAmount: discountAmount,
      );
    }
  }

  Future<Order> _placeOnline({
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    required double taxRate,
    required double discountAmount,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount;

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

    final order = Order.fromMap(orderRow, items: items);

    // Deduct inventory
    await _deductInventory(businessId, items);

    // Cache locally
    await _local.upsertOrders([order]);

    return order;
  }

  Future<Order> _placeOffline({
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    required double taxRate,
    required double discountAmount,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount;

    // Generate a local UUID — Supabase will accept it on sync
    final offlineId = const Uuid().v4();
    final now = DateTime.now();

    // Local order number: timestamp-based to avoid collisions
    final localOrderNumber = now.millisecondsSinceEpoch % 100000;

    final order = Order(
      id: offlineId,
      businessId: businessId,
      tableId: tableId,
      cashierId: _client.auth.currentUser?.id,
      orderNumber: localOrderNumber,
      orderType: tableId != null ? OrderType.walkIn : OrderType.walkIn,
      status: OrderStatus.pending,
      subtotal: subtotal,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      totalAmount: totalAmount,
      notes: notes,
      createdAt: now,
      items: items,
    );

    // Persist locally
    await _local.insertOfflineOrder(order);

    // Queue for Supabase
    final itemPayloads = items
        .map((i) => {
              'order_id': offlineId,
              'product_id': i.product.id,
              'product_name': i.product.name,
              'unit_price': i.product.price,
              'quantity': i.quantity,
              'subtotal': i.total,
            })
        .toList();

    await _syncQueue.enqueue(
      operation: 'insert_order',
      tableName: 'orders',
      recordId: offlineId,
      payload: {
        'id': offlineId,
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
        'created_at': now.toIso8601String(),
        'items': itemPayloads,
      },
    );

    // Deduct inventory locally
    await _deductInventory(businessId, items);

    return order;
  }

  // ── Update status ───────────────────────────────────────────────────────────

  Future<void> updateStatus(String orderId, OrderStatus status) async {
    if (_isOnline) {
      try {
        await _client.from('orders').update({
          'status': status.value,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);
        return;
      } catch (e) {
        debugPrint('[OrderService] updateStatus online failed, queuing: $e');
      }
    }
    await _syncQueue.enqueue(
      operation: 'update_order_status',
      tableName: 'orders',
      recordId: orderId,
      payload: {'status': status.value},
    );
  }

  // ── Process payment ─────────────────────────────────────────────────────────

  Future<void> processPayment({
    required String orderId,
    required PaymentMethod method,
    required double amountTendered,
    required double changeAmount,
  }) async {
    final payload = {
      'payment_method': method.value,
      'amount_tendered': amountTendered,
      'change_amount': changeAmount,
      'paid_at': DateTime.now().toIso8601String(),
    };

    if (_isOnline) {
      try {
        await _client.from('orders').update({
          ...payload,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);
        return;
      } catch (e) {
        debugPrint('[OrderService] processPayment online failed, queuing: $e');
      }
    }
    await _syncQueue.enqueue(
      operation: 'process_payment',
      tableName: 'orders',
      recordId: orderId,
      payload: payload,
    );
  }

  // ── Fetch single order ──────────────────────────────────────────────────────

  Future<Order> fetchOrderWithItems(String orderId) async {
    if (_isOnline) {
      try {
        final orderRow = await _client
            .from('orders')
            .select()
            .eq('id', orderId)
            .single();

        final itemRows = await _client
            .from('order_items')
            .select(
                '*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active)')
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
      } catch (e) {
        debugPrint('[OrderService] fetchOrderWithItems online failed, using cache: $e');
      }
    }

    // Offline fallback
    final profile = await _ref.read(profileProvider.future);
    final businessId = profile?.businessId ?? '';
    final orders = await _local.getOrders(businessId);  // ← was getOrders('')
    final cached = orders.where((o) => o.id == orderId).firstOrNull;
    if (cached != null) return cached;
    throw Exception('Order $orderId not found in local cache');
      }
  // ── Inventory deduction helper ──────────────────────────────────────────────

  Future<void> _deductInventory(
      String businessId, List<CartItem> items) async {
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
      _ref.invalidate(productListProvider);
    } catch (e) {
      debugPrint('[OrderService] Inventory deduction error (non-fatal): $e');
    }
  }
}

// ── LEGACY: kept for backward compat ─────────────────────────────────────────

class OrderNotifier extends StateNotifier<List<Order>> {
  OrderNotifier() : super([]);
  void updateStatus(String orderId, String status) {}
  void removeOrder(String orderId) {}
}

final orderProvider = StateNotifierProvider<OrderNotifier, List<Order>>(
  (ref) => OrderNotifier(),
);