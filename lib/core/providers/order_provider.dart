// lib/core/providers/order_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/promo.dart';
import '../models/void_record.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';
import '../providers/app_context_provider.dart';
import '../services/event_bus.dart';
import 'product_provider.dart';
import '../models/order_payment.dart';


// ── Cache invalidation signal ─────────────────────────────────────────────────
// Add an order ID here to force its items to be re-fetched on the next
// realtime emission. Used by voidOrderItem and voidOrder.

final _invalidatedOrderIdsProvider = StateProvider<Set<String>>((ref) => {});

void invalidateOrderCache(Ref ref, String orderId) {
  final notifier = ref.read(_invalidatedOrderIdsProvider.notifier);
  notifier.state = {...notifier.state, orderId};
}

// ── Live / cached order stream ────────────────────────────────────────────────

final ordersStreamProvider = StreamProvider<List<Order>>((ref) async* {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) {
    yield [];
    return;
  }
  final local = ref.read(localDbServiceProvider);
  // Item cache: avoid re-fetching items for orders that haven't changed.
  final itemCache = <String, List<CartItem>>{};

  // Watch invalidation signals — evict specific orders when voided/updated.
  ref.listen<Set<String>>(_invalidatedOrderIdsProvider, (_, invalidated) {
    for (final id in invalidated) {
      itemCache.remove(id);
    }
    // Clear the signal after processing
    ref.read(_invalidatedOrderIdsProvider.notifier).state = {};
  });

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

  // Limit to last 30 days — older orders are in local cache / reports.
  final cutoff = DateTime.now()
      .subtract(const Duration(days: 30))
      .toUtc()
      .toIso8601String();

  yield* client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('business_id', businessId)
      .order('created_at', ascending: false)
      .asyncMap((rows) async {
        // Filter to last 30 days client-side since .stream() doesn't
        // support .gte() date filters directly.
        final filtered = (rows as List)
            .where((r) => (r['created_at'] as String).compareTo(cutoff) >= 0)
            .toList();
        if (filtered.isEmpty) return <Order>[];

        final orderIds = filtered.map((r) => r['id'] as String).toList();

        // Only fetch items for orders not already in cache.
        final uncachedIds = orderIds
            .where((id) => !itemCache.containsKey(id))
            .toList();

        if (uncachedIds.isNotEmpty) {
          final allItemRows = await client
              .from('order_items')
              .select(
                  '*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active, send_to_kitchen)')
              .inFilter('order_id', uncachedIds);

          final rowsByOrder = <String, List<Map<String, dynamic>>>{};
          for (final item in allItemRows as List) {
            final row = item as Map<String, dynamic>;
            rowsByOrder
                .putIfAbsent(row['order_id'] as String, () => [])
                .add(row);
          }

          for (final entry in rowsByOrder.entries) {
            itemCache[entry.key] = CartItem.groupOrderItemRows<Map<String, dynamic>>(
              entry.value,
              promoGroupId: (row) => row['promo_group_id'] as String?,
              isHeaderRow: (row) => row['product_id'] == null,
              buildItem: (row) {
                if (row['product_id'] == null) {
                  return CartItem(
                    product: Product.promo(
                      id: 'promo_${row['promo_id']}',
                      name: row['product_name'] as String,
                      price: (row['unit_price'] as num).toDouble(),
                    ),
                    quantity: row['quantity'] as int,
                    costAtSale: (row['cost_price'] as num?)?.toDouble() ?? 0,
                    notes: row['notes'] as String?,
                    promoId: row['promo_id'] as String?,
                  );
                }
                final pMap = row['products'] as Map<String, dynamic>? ?? {};
                final product = Product.fromMap({
                  ...pMap,
                  'category': '',
                  'business_id': pMap['business_id'] ?? '',
                });
                return CartItem(
                  product: product,
                  quantity: row['quantity'] as int,
                  costAtSale: (row['cost_price'] as num?)?.toDouble() ?? 0,
                  notes: row['notes'] as String?,
                );
              },
              buildComponent: (row) {
                final pMap = row['products'] as Map<String, dynamic>? ?? {};
                return PromoComponent(
                  promoId: row['promo_id'] as String? ?? '',
                  productId: row['product_id'] as String,
                  productName: row['product_name'] as String,
                  quantity: row['quantity'] as int,
                  trackInventory: pMap['track_inventory'] as bool? ?? false,
                  sendToKitchen: pMap['send_to_kitchen'] as bool? ?? true,
                );
              },
            );
          }
        }

        // Evict orders no longer in the stream window to prevent unbounded growth.
        itemCache.removeWhere((id, _) => !orderIds.contains(id));

        final orders = filtered.map((row) {
          final orderId = row['id'] as String;
          return Order.fromMap(
              row, items: itemCache[orderId] ?? []);
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
    OrderType orderType = OrderType.walkIn,
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
        orderType: orderType,
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
        orderType: orderType,
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
    OrderType orderType = OrderType.walkIn,
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
          'order_type': tableId != null ? 'walk_in' : orderType.value,
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
        .expand((item) => _buildOnlineRows(orderId, item))
        .toList();

    await _client.from('order_items').insert(orderItems);

    final order = Order.fromMap(orderRow, items: items);

    await _deductInventory(businessId, items);
    await _local.upsertOrders([order]);

    _ref.invalidate(productListProvider);

    EventBus.instance.emit(AppEvents.orderPlaced, {
      'order_id': order.id,
      'business_id': businessId,
    });

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
    OrderType orderType = OrderType.walkIn,
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
      orderType: tableId != null ? OrderType.walkIn : orderType,
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
        .expand((i) => _buildOfflineRows(i))
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
        'order_type': tableId != null ? 'walk_in' : orderType.value,
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

    EventBus.instance.emit(AppEvents.orderPlaced, {
      'order_id': order.id,
      'business_id': businessId,
    });

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
        EventBus.instance.emit(AppEvents.orderStatusChanged, {
          'order_id': orderId,
          'status': status.value,
        });
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
    EventBus.instance.emit(AppEvents.orderStatusChanged, {
      'order_id': orderId,
      'status': status.value,
    });
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

    // ── Process a SPLIT payment (Task 3) ────────────────────────────────────────
  //
  // Records N payment legs against one order. Does not replace
  // processPayment — a normal single-method checkout still calls that
  // unchanged. orders.payment_method/amount_tendered/change_amount are kept
  // populated with the dominant leg for backward compatibility with any
  // code reading those columns directly; order_payments is the real
  // breakdown and is_split_payment marks the order as one to look up.
  Future<List<OrderPayment>> processSplitPayment({
    required String orderId,
    required String businessId,
    required List<PaymentSplitInput> payments,
    double changeAmount = 0,
  }) async {
    assert(payments.isNotEmpty, 'processSplitPayment requires at least one payment leg');

    final now = DateTime.now();
    final primary = payments.reduce((a, b) => b.amount > a.amount ? b : a);
    final cashTendered =
        payments.where((p) => p.method == PaymentMethod.cash).fold(0.0, (s, p) => s + p.amount);

    // Order total isn't passed in here — caller (CheckoutService) already
    // validated remaining <= 0 before calling this, so any excess is a
    // genuine cash overpayment/change, not a data error.
    final orderPayments = payments
        .map((p) => OrderPayment(
              id: const Uuid().v4(),
              orderId: orderId,
              businessId: businessId,
              method: p.method,
              amount: p.amount,
              referenceNumber: p.referenceNumber,
              createdAt: now,
            ))
        .toList();

    final rows = orderPayments.map((p) => p.toMap()).toList();

    // Local write first — same pattern as processPayment.
    await _local.insertOrderPayments(
      rows,
      orderId: orderId,
      primaryMethod: primary.method,
      amountTendered: cashTendered,
      changeAmount: changeAmount,
    );

    if (_isOnline) {
      try {
        await _client.from('order_payments').insert(rows);
        await _client.from('orders').update({
          'payment_method': primary.method.value,
          'amount_tendered': cashTendered,
          'change_amount': changeAmount,
          'is_split_payment': true,
          'paid_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        }).eq('id', orderId);
        return orderPayments;
      } catch (e) {
        debugPrint('[OrderService] processSplitPayment online failed, queuing: $e');
      }
    }

    await _syncQueue.enqueue(
      operation: 'process_split_payment',
      tableName: 'order_payments',
      recordId: orderId,
      payload: {
        'order_id': orderId,
        'business_id': businessId,
        'payments': rows,
        'primary_method': primary.method.value,
        'amount_tendered': cashTendered,
        'change_amount': changeAmount,
      },
    );

    return orderPayments;
  }

  /// Fetches the payment breakdown for an order — empty list for a normal
  /// single-payment order (nothing was ever written to order_payments).
  Future<List<OrderPayment>> getOrderPayments(String orderId) async {
    if (_isOnline) {
      try {
        final rows = await _client
            .from('order_payments')
            .select()
            .eq('order_id', orderId)
            .order('created_at');
        return (rows as List)
            .map((r) => OrderPayment.fromMap(r as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[OrderService] getOrderPayments online failed, using cache: $e');
      }
    }
    return _local.getOrderPayments(orderId);
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
    String? variantId,
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

    // 1b. Invalidate item cache so the stream re-fetches this order's items.
    invalidateOrderCache(_ref, orderId);

    // 2. Reverse inventory if the product tracks stock.
    if (trackInventory) {
      try {
        final inventoryService = _ref.read(inventoryServiceProvider);
        // variantId is non-null when the voided item was a variant sale
        if (variantId != null) {
          await inventoryService.adjustVariantStock(
            businessId: businessId,
            productId: productId,
            variantId: variantId,
            quantityChange: quantity,
            quantityBefore: currentStock,
            action: 'void',
          );
        } else {
          await inventoryService.adjustStock(
            businessId: businessId,
            productId: productId,
            quantityChange: quantity,
            quantityBefore: currentStock,
            action: 'void',
          );
        }
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
            .eq('product_id', productId)
            .limit(1);

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

        EventBus.instance.emit(AppEvents.orderStatusChanged, {
          'order_id': orderId,
        });

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

    EventBus.instance.emit(AppEvents.orderStatusChanged, {
      'order_id': orderId,
    });

    debugPrint(
        '[OrderService] voidOrderItem queued for sync: $voidId');
    return voidRecord;
  }

  // ── Void entire order ───────────────────────────────────────────────────────

  Future<void> voidOrder({
    required String orderId,
    required String businessId,
    required String reason,
    required String voidedByStaffId,
    required String voidedByStaffName,
    required List<CartItem> items,
  }) async {
    final now = DateTime.now();

    // 1. Cancel locally
    await _local.markOrderStatus(orderId, OrderStatus.cancelled);

    // 1b. Record void rows locally — one row per plain item, or a header
    // + component rows per promo (_buildVoidRows), so getVoidedItemsForOrder
    // has something to show and this survives offline regardless of when
    // (or whether) the Supabase sync below succeeds.
    final localVoidRows = <Map<String, dynamic>>[];
    for (final item in items) {
      for (final row in _buildVoidRows(item)) {
        final id = const Uuid().v4();
        localVoidRows.add({
          'id': id,
          'order_id': orderId,
          ...row,
          'reason': reason,
          'voided_by_staff_id': voidedByStaffId,
          'voided_by_staff_name': voidedByStaffName,
          'voided_at': now.toIso8601String(),
          'synced': 0,
        });
      }
    }
    await _local.recordVoidedItems(localVoidRows);

    // 1c. Invalidate item cache for this order.
    invalidateOrderCache(_ref, orderId);

    EventBus.instance.emit(AppEvents.orderStatusChanged, {
      'order_id': orderId,
      'status': 'cancelled',
    });

    // 2. Reverse inventory for all items
    try {
      final inventoryService = _ref.read(inventoryServiceProvider);
      for (final item in items) {
        if (item.isPromo) {
          await _reversePromoComponents(businessId, item, inventoryService);
          continue;
        }
        if (!item.product.trackInventory) continue;
        if (item.selectedVariant != null) {
          final freshVariants =
              await _local.getVariantsForProduct(item.product.id);
          final freshVariant = freshVariants
              .where((v) => v.id == item.selectedVariant!.id)
              .firstOrNull;
          await inventoryService.adjustVariantStock(
            businessId: businessId,
            productId: item.product.id,
            variantId: item.selectedVariant!.id,
            quantityChange: item.quantity,
            quantityBefore:
                freshVariant?.stockQuantity ?? item.selectedVariant!.stockQuantity,
            action: 'void',
          );
        } else {
          final freshProducts = await _local.getProducts(businessId);
          final freshProduct = freshProducts
              .where((p) => p.id == item.product.id)
              .firstOrNull;
          await inventoryService.adjustStock(
            businessId: businessId,
            productId: item.product.id,
            quantityChange: item.quantity,
            quantityBefore:
                freshProduct?.stockQuantity ?? item.product.stockQuantity,
            action: 'void',
          );
        }
      }
      _ref.invalidate(productListProvider);
    } catch (e) {
      debugPrint('[OrderService] voidOrder inventory reversal error: $e');
    }

    // 3. Sync or enqueue
    if (_isOnline) {
      try {
        await _client.from('orders').update({
          'status': OrderStatus.cancelled.value,
          'notes': reason,
          'updated_at': now.toIso8601String(),
        }).eq('id', orderId);

        // Void each item row in Supabase — header (promo money) +
        // component rows for a promo line, same pattern as order_items.
        // Reuses the ids already written locally so both sides agree,
        // and marks each row synced once its insert succeeds.
        for (final localRow in localVoidRows) {
          final id = localRow['id'] as String;
          await _client.from('void_order_items').insert({
            ...localRow..remove('synced'),
          });
          await _local.markVoidSynced(id);
        }

        // Void the receipt if one exists
        await _client
            .from('receipts')
            .update({
              'is_voided': true,
              'voided_at': now.toIso8601String(),
              'voided_by': voidedByStaffId,
              'void_reason': reason,
              'updated_at': now.toIso8601String(),
            })
            .eq('order_id', orderId)
            .eq('is_voided', false);

        debugPrint('[OrderService] voidOrder synced: $orderId');
        return;
      } catch (e) {
        debugPrint('[OrderService] voidOrder online failed, queuing: $e');
      }
    }

    // Offline path
    await _syncQueue.enqueue(
      operation: 'void_order',
      tableName: 'orders',
      recordId: orderId,
      idempotencyKey: '${orderId}_void',
      payload: {
        'order_id': orderId,
        'business_id': businessId,
        'reason': reason,
        'voided_by_staff_id': voidedByStaffId,
        'voided_by_staff_name': voidedByStaffName,
        'voided_at': now.toIso8601String(),
        'items': localVoidRows,
      },
    );

    debugPrint('[OrderService] voidOrder queued: $orderId');
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
                costAtSale: (row['cost_price'] as num?)?.toDouble() ?? 0,
                notes: row['notes'] as String?);
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

  // ── Promo → order_items expansion ─────────────────────────────────────────
  //
  // A promo cart line becomes N+1 rows sharing one promo_group_id:
  //   - one header row (product_id = null, carries the actual money —
  //     unit_price/subtotal/cost) so revenue isn't double-counted
  //   - one row per underlying product (product_id = real product, quantity
  //     = component qty × cart qty, unit_price/subtotal = 0) so inventory
  //     deduction and future kitchen/receipt grouping have something to key
  //     off. Supabase order_items has no variant_id column, so a component's
  //     variant is folded into product_name here.

  /// Row shape for a void record. Mirrors order_items' own header+component
  /// pattern now that void_order_items has promo_id/promo_group_id and a
  /// nullable product_id: a promo void is one header row (product_id null,
  /// carries the real refunded amount) plus one row per real component
  /// (zero money) for the audit trail — so void_order_items' subtotal sum
  /// matches the order total again, and "what was voided" is still fully
  /// itemized.
  List<Map<String, dynamic>> _buildVoidRows(CartItem item) {
    if (!item.isPromo) {
      return [
        {
          'product_id': item.product.id,
          'product_name': item.product.name,
          'unit_price': item.effectivePrice,
          'quantity': item.quantity,
          'subtotal': item.total,
        }
      ];
    }
    final groupId = const Uuid().v4();
    return [
      {
        'product_id': null,
        'product_name': item.product.name,
        'unit_price': item.effectivePrice,
        'quantity': item.quantity,
        'subtotal': item.total,
        'promo_id': item.promoId,
        'promo_group_id': groupId,
      },
      for (final c in item.promoComponents!)
        {
          'product_id': c.productId,
          'product_name':
              c.variantName != null ? '${c.productName} (${c.variantName})' : c.productName,
          'unit_price': 0,
          'quantity': c.quantity * item.quantity,
          'subtotal': 0,
          'promo_id': item.promoId,
          'promo_group_id': groupId,
        },
    ];
  }

  List<Map<String, dynamic>> _buildOnlineRows(String orderId, CartItem item) {
    if (!item.isPromo) {
      return [
        {
          'order_id': orderId,
          'product_id': item.product.id,
          'product_name': item.product.name,
          'unit_price': item.effectivePrice,
          'cost_price': item.costAtSale,
          'quantity': item.quantity,
          'subtotal': item.total,
          'cost_at_sale': _effectiveCost(item),
          'notes': item.notes,
        }
      ];
    }
    final groupId = const Uuid().v4();
    return [
      {
        'order_id': orderId,
        'product_id': null,
        'product_name': item.product.name,
        'unit_price': item.effectivePrice,
        'cost_price': item.costAtSale,
        'quantity': item.quantity,
        'subtotal': item.total,
        'cost_at_sale': _effectiveCost(item),
        'notes': item.notes,
        'promo_id': item.promoId,
        'promo_group_id': groupId,
      },
      for (final c in item.promoComponents!)
        {
          'order_id': orderId,
          'product_id': c.productId,
          'product_name':
              c.variantName != null ? '${c.productName} (${c.variantName})' : c.productName,
          'unit_price': 0,
          'cost_price': 0,
          'quantity': c.quantity * item.quantity,
          'subtotal': 0,
          'cost_at_sale': 0,
          'notes': null,
          'promo_id': item.promoId,
          'promo_group_id': groupId,
        },
    ];
  }

  List<Map<String, dynamic>> _buildOfflineRows(CartItem item) {
    if (!item.isPromo) {
      return [
        {
          'product_id': item.product.id,
          'product_name': item.product.name,
          'unit_price': item.effectivePrice,
          'quantity': item.quantity,
          'subtotal': item.total,
          'cost_at_sale': _effectiveCost(item),
          'notes': item.notes,
        }
      ];
    }
    final groupId = const Uuid().v4();
    return [
      {
        'product_id': null,
        'product_name': item.product.name,
        'unit_price': item.effectivePrice,
        'quantity': item.quantity,
        'subtotal': item.total,
        'cost_at_sale': _effectiveCost(item),
        'notes': item.notes,
        'promo_id': item.promoId,
        'promo_group_id': groupId,
      },
      for (final c in item.promoComponents!)
        {
          'product_id': c.productId,
          'product_name':
              c.variantName != null ? '${c.productName} (${c.variantName})' : c.productName,
          'unit_price': 0,
          'quantity': c.quantity * item.quantity,
          'subtotal': 0,
          'cost_at_sale': 0,
          'notes': null,
          'promo_id': item.promoId,
          'promo_group_id': groupId,
        },
    ];
  }

  // ── Inventory deduction ─────────────────────────────────────────────────────

  Future<void> _deductInventory(
      String businessId, List<CartItem> items) async {
    try {
      final inventoryService = _ref.read(inventoryServiceProvider);
      for (final item in items) {
        if (item.isPromo) {
          await _deductPromoComponents(businessId, item, inventoryService);
          continue;
        }
        if (!item.product.trackInventory) continue;

        if (item.selectedVariant != null) {
          final freshVariants = await _local.getVariantsForProduct(item.product.id);
          final freshVariant = freshVariants
              .where((v) => v.id == item.selectedVariant!.id)
              .firstOrNull;
          final quantityBefore = freshVariant?.stockQuantity ?? item.selectedVariant!.stockQuantity;
          await inventoryService.adjustVariantStock(
            businessId: businessId,
            productId: item.product.id,
            variantId: item.selectedVariant!.id,
            quantityChange: -item.quantity,
            quantityBefore: quantityBefore,
            action: 'sale',
          );
        } else {
          final freshProducts = await _local.getProducts(businessId);
          final freshProduct = freshProducts
              .where((p) => p.id == item.product.id)
              .firstOrNull;
          final quantityBefore = freshProduct?.stockQuantity ?? item.product.stockQuantity;
          await inventoryService.adjustStock(
            businessId: businessId,
            productId: item.product.id,
            quantityChange: -item.quantity,
            quantityBefore: quantityBefore,
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

  Future<void> _reversePromoComponents(
      String businessId, CartItem promoItem, dynamic inventoryService) async {
    for (final c in promoItem.promoComponents!) {
      if (!c.trackInventory) continue;
      final totalQty = c.quantity * promoItem.quantity;

      if (c.variantId != null) {
        final freshVariants = await _local.getVariantsForProduct(c.productId);
        final freshVariant =
            freshVariants.where((v) => v.id == c.variantId).firstOrNull;
        await inventoryService.adjustVariantStock(
          businessId: businessId,
          productId: c.productId,
          variantId: c.variantId!,
          quantityChange: totalQty,
          quantityBefore: freshVariant?.stockQuantity ?? 0,
          action: 'void',
        );
      } else {
        final freshProducts = await _local.getProducts(businessId);
        final freshProduct =
            freshProducts.where((p) => p.id == c.productId).firstOrNull;
        await inventoryService.adjustStock(
          businessId: businessId,
          productId: c.productId,
          quantityChange: totalQty,
          quantityBefore: freshProduct?.stockQuantity ?? 0,
          action: 'void',
        );
      }
    }
  }

  Future<void> _deductPromoComponents(
      String businessId, CartItem promoItem, dynamic inventoryService) async {
    for (final c in promoItem.promoComponents!) {
      if (!c.trackInventory) continue;
      final totalQty = c.quantity * promoItem.quantity;

      if (c.variantId != null) {
        final freshVariants = await _local.getVariantsForProduct(c.productId);
        final freshVariant =
            freshVariants.where((v) => v.id == c.variantId).firstOrNull;
        await inventoryService.adjustVariantStock(
          businessId: businessId,
          productId: c.productId,
          variantId: c.variantId!,
          quantityChange: -totalQty,
          quantityBefore: freshVariant?.stockQuantity ?? 0,
          action: 'sale',
        );
      } else {
        final freshProducts = await _local.getProducts(businessId);
        final freshProduct =
            freshProducts.where((p) => p.id == c.productId).firstOrNull;
        await inventoryService.adjustStock(
          businessId: businessId,
          productId: c.productId,
          quantityChange: -totalQty,
          quantityBefore: freshProduct?.stockQuantity ?? 0,
          action: 'sale',
        );
      }
    }
  }
}