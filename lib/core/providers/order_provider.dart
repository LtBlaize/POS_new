// lib/core/providers/order_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/void_record.dart';
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

  final cached = await local.getOrders(businessId);
  if (cached.isNotEmpty) yield cached;

  if (!ref.read(isOnlineProvider)) {
    final completer = Completer<void>();
    final sub = ref.listen<bool>(isOnlineProvider, (_, next) {
      if (next && !completer.isCompleted) completer.complete();
    });
    await completer.future;
    sub.close();

    final refreshed = await local.getOrders(businessId);
    yield refreshed;
  }

  final client = ref.watch(supabaseClientProvider);

  yield* client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('business_id', businessId)
      .order('created_at', ascending: false)
      .asyncMap((rows) async {
        if (rows.isEmpty) return <Order>[];

        final orderIds = rows.map((r) => r['id'] as String).toList();

        final allItemRows = await client
            .from('order_items')
            .select(
                '*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active)')
            .inFilter('order_id', orderIds);

        final itemsByOrder = <String, List<CartItem>>{};
          for (final item in allItemRows as List) {
            final orderId = item['order_id'] as String;
            final pMap =
                item['products'] as Map<String, dynamic>? ?? {};
            final product = Product.fromMap({
              ...pMap,
              'category': '',
              'business_id': pMap['business_id'] ?? '',
            });
            itemsByOrder
                .putIfAbsent(orderId, () => [])
                .add(CartItem(
                    product: product,
                    quantity: item['quantity'] as int,
                    costAtSale: (item['cost_price'] as num?)?.toDouble() ?? 0));
          }

        final orders = rows.map((row) {
          final orderId = row['id'] as String;
          return Order.fromMap(
              row, items: itemsByOrder[orderId] ?? []);
        }).toList();

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
  return orders
      .where((o) => o.status == OrderStatus.completed)
      .toList();
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
    double tipAmount = 0.0,
    String? cashierId,
  }) async {
    if (_isOnline) {
      return _placeOnline(
        businessId: businessId,
        items: items,
        tableId: tableId,
        notes: notes,
        taxRate: taxRate,
        discountAmount: discountAmount,
        tipAmount: tipAmount,
        cashierId: cashierId,
      );
    } else {
      return _placeOffline(
        businessId: businessId,
        items: items,
        tableId: tableId,
        notes: notes,
        taxRate: taxRate,
        discountAmount: discountAmount,
        tipAmount: tipAmount,
        cashierId: cashierId,
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
    double tipAmount = 0.0,
    String? cashierId,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount + tipAmount;

    final orderRow = await _client
        .from('orders')
        .insert({
          'business_id': businessId,
          'table_id': tableId,
          'cashier_id': cashierId,
          'order_type': tableId != null ? 'dine_in' : 'walk_in',
          'status': 'pending',
          'subtotal': subtotal,
          'tax_amount': taxAmount,
          'discount_amount': discountAmount,
          'tip_amount': tipAmount,
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
              'cost_price': item.costAtSale,
              'quantity': item.quantity,
              'subtotal': item.total,
              'cost_at_sale': _effectiveCost(item),
            })
        .toList();

    await _client.from('order_items').insert(orderItems);

    final order = Order.fromMap(orderRow, items: items);

    await _deductInventory(businessId, items);
    await _local.upsertOrders([order]);

    _ref.invalidate(productListProvider);

    return order;
  }

  Future<Order> _placeOffline({
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    required double taxRate,
    required double discountAmount,
    double tipAmount = 0.0,
    String? cashierId,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount + tipAmount;

    final offlineId = const Uuid().v4();
    final now = DateTime.now();
    final localOrderNumber = now.millisecondsSinceEpoch;

    final order = Order(
      id: offlineId,
      businessId: businessId,
      tableId: tableId,
      cashierId: cashierId,
      orderNumber: localOrderNumber,
      orderType: OrderType.walkIn,
      status: OrderStatus.pending,
      subtotal: subtotal,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      tipAmount: tipAmount,
      totalAmount: totalAmount,
      notes: notes,
      createdAt: now,
      items: items,
    );

    await _local.insertOfflineOrder(order);

    final itemPayloads = items
        .map((i) => {
              'order_id': offlineId,
              'product_id': i.product.id,
              'product_name': i.product.name,
              'unit_price': i.effectivePrice,
              'quantity': i.quantity,
              'subtotal': i.total,
              'cost_at_sale': _effectiveCost(i),
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
        'cashier_id': cashierId,
        'order_type': tableId != null ? 'dine_in' : 'walk_in',
        'status': 'pending',
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'tip_amount': tipAmount,
        'total_amount': totalAmount,
        'notes': notes,
        'created_at': now.toIso8601String(),
        'items': itemPayloads,
      },
    );

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
        debugPrint(
            '[OrderService] updateStatus online failed, queuing: $e');
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
    String? referenceNumber,
  }) async {
    final payload = {
      'payment_method': method.value,
      'amount_tendered': amountTendered,
      'change_amount': changeAmount,
      'reference_number': referenceNumber,
      'paid_at': DateTime.now().toIso8601String(),
    };

    if (_isOnline) {
      try {
        await _client.from('orders').update({
          ...payload,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);

        await _local.updateOrderPayment(
          orderId: orderId,
          method: method,
          amountTendered: amountTendered,
          changeAmount: changeAmount,
          referenceNumber: referenceNumber,
        );
        return;
      } catch (e) {
        debugPrint(
            '[OrderService] processPayment online failed, queuing: $e');
      }
    }

    await _local.updateOrderPayment(
      orderId: orderId,
      method: method,
      amountTendered: amountTendered,
      changeAmount: changeAmount,
      referenceNumber: referenceNumber,
    );

    await _syncQueue.enqueue(
      operation: 'process_payment',
      tableName: 'orders',
      recordId: orderId,
      payload: payload,
    );
  }

  // ── Void a single item from an existing order ───────────────────────────────

  /// Voids [quantity] units of [productId] from [orderId].
  ///
  /// - Removes the order_item row locally and recalculates totals atomically.
  /// - Reverses inventory for tracked products.
  /// - If the order has no items left, status becomes [OrderStatus.cancelled].
  /// - Persists a [VoidRecord] locally and syncs to Supabase when online,
  ///   or enqueues for later sync when offline.
  Future<VoidRecord> voidOrderItem({
    required String orderId,
    required String productId,
    required String productName,
    required double unitPrice,
    required int quantity,
    required String reason,
    required String voidedByStaffId,
    required String voidedByStaffName,
    required String businessId,
    bool trackInventory = false,
    int currentStock = 0,
  }) async {
    final voidId = const Uuid().v4();
    final subtotal = unitPrice * quantity;
    final now = DateTime.now();

    // 1. Persist locally — atomic transaction: insert void, delete item,
    //    recalculate order totals (or cancel if last item).
    await _local.voidOrderItem(
      voidId: voidId,
      orderId: orderId,
      productId: productId,
      productName: productName,
      unitPrice: unitPrice,
      quantity: quantity,
      subtotal: subtotal,
      reason: reason,
      voidedByStaffId: voidedByStaffId,
      voidedByStaffName: voidedByStaffName,
    );

    // 2. Reverse inventory if the product tracks stock.
    if (trackInventory) {
      try {
        final inventoryService = _ref.read(inventoryServiceProvider);
        await inventoryService.adjustStock(
          businessId: businessId,
          productId: productId,
          quantityChange: quantity, // positive = restoring stock
          quantityBefore: currentStock,
          action: 'void',
        );
        _ref.invalidate(productListProvider);
      } catch (e) {
        debugPrint(
            '[OrderService] Inventory reversal error (non-fatal): $e');
      }
    }

    final voidRecord = VoidRecord(
      id: voidId,
      orderId: orderId,
      productId: productId,
      productName: productName,
      unitPrice: unitPrice,
      quantity: quantity,
      subtotal: subtotal,
      reason: reason,
      voidedByStaffId: voidedByStaffId,
      voidedByStaffName: voidedByStaffName,
      voidedAt: now,
    );

    // 3. Sync to Supabase when online.
    if (_isOnline) {
      try {
        // Insert the void record
        await _client
            .from('void_order_items')
            .insert(voidRecord.toMap());

        // Remove item from Supabase order_items
        await _client
            .from('order_items')
            .delete()
            .eq('order_id', orderId)
            .eq('product_id', productId);

        // Fetch remaining items to decide order fate
        final remaining = await _client
            .from('order_items')
            .select('subtotal')
            .eq('order_id', orderId);

        if ((remaining as List).isEmpty) {
          // No items left — cancel in Supabase
          await _client.from('orders').update({
            'status': OrderStatus.cancelled.value,
            'updated_at': now.toIso8601String(),
          }).eq('id', orderId);
        } else {
          // Recalculate totals in Supabase
          final newSubtotal = remaining.fold<double>(
            0,
            (s, r) => s + (r['subtotal'] as num).toDouble(),
          );

          final orderRow = await _client
              .from('orders')
              .select('tax_amount, discount_amount, subtotal')
              .eq('id', orderId)
              .single();

          final oldSubtotal =
              (orderRow['subtotal'] as num).toDouble();
          final existingTax =
              (orderRow['tax_amount'] as num).toDouble();
          final existingDiscount =
              (orderRow['discount_amount'] as num).toDouble();

          final taxRate =
              oldSubtotal > 0 ? existingTax / oldSubtotal : 0.0;
          final newTax = newSubtotal * taxRate;
          final newDiscount =
              existingDiscount.clamp(0.0, newSubtotal);
          final newTotal = newSubtotal + newTax - newDiscount;

          await _client.from('orders').update({
            'subtotal': newSubtotal,
            'tax_amount': newTax,
            'discount_amount': newDiscount,
            'total_amount': newTotal,
            'updated_at': now.toIso8601String(),
          }).eq('id', orderId);
        }

        // Mark local void record as synced
        await _local.markVoidSynced(voidId);

        debugPrint(
            '[OrderService] voidOrderItem synced to Supabase: $voidId');
        return voidRecord;
      } catch (e) {
        debugPrint(
            '[OrderService] voidOrderItem online failed, queuing: $e');
        // Fall through to enqueue below
      }
    }

    // 4. Offline (or online-failed) — enqueue for later sync.
    await _syncQueue.enqueue(
      operation: 'void_order_item',
      tableName: 'void_order_items',
      recordId: voidId,
      payload: {
        ...voidRecord.toMap(),
        'track_inventory': trackInventory,
        'current_stock': currentStock,
        'business_id': businessId,
      },
    );

    debugPrint(
        '[OrderService] voidOrderItem queued for sync: $voidId');
    return voidRecord;
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
            final pMap =
                row['products'] as Map<String, dynamic>? ?? {};
            final product = Product.fromMap({
              ...pMap,
              'category': '',
              'business_id': pMap['business_id'] ?? '',
            });
            return CartItem(
                product: product,
                quantity: row['quantity'] as int,
                costAtSale: (row['cost_price'] as num?)?.toDouble() ?? 0);
          }).toList();

        return Order.fromMap(orderRow, items: cartItems);
      } catch (e) {
        debugPrint(
            '[OrderService] fetchOrderWithItems online failed, using cache: $e');
      }
    }

    final profile = await _ref.read(profileProvider.future);
    final businessId = profile?.businessId ?? '';
    final orders = await _local.getOrders(businessId);
    final cached = orders.where((o) => o.id == orderId).firstOrNull;
    if (cached != null) return cached;
    throw Exception('Order $orderId not found in local cache');
  }

  // ── Cost resolution ─────────────────────────────────────────────────────────

  double _effectiveCost(CartItem item) {
    if (item.selectedVariant != null && item.selectedVariant!.costPrice > 0) {
      return item.selectedVariant!.costPrice;
    }
    return item.product.costPrice;
  }

  // ── Inventory deduction ─────────────────────────────────────────────────────

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
      debugPrint(
          '[OrderService] Inventory deduction error (non-fatal): $e');
    }
  }
}

// ── DEAD CODE — do not use ────────────────────────────────────────────────────
// Kitchen uses kitchenStateProvider.
// POS uses orderServiceProvider.
// This stub exists for backward compat only.

class OrderNotifier extends StateNotifier<List<Order>> {
  OrderNotifier() : super([]);
  void updateStatus(String orderId, String status) {}
  void removeOrder(String orderId) {}
}

final orderProvider = StateNotifierProvider<OrderNotifier, List<Order>>(
  (ref) => OrderNotifier(),
);