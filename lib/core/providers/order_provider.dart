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
import '../models/product_variant.dart';


// ── Cache invalidation signal ─────────────────────────────────────────────────
// Add an order ID here to force its items to be re-fetched on the next
// realtime emission. Used by voidOrderItem and voidOrder.

final _invalidatedOrderIdsProvider = StateProvider<Set<String>>((ref) => {});

void invalidateOrderCache(Ref ref, String orderId) {
  final notifier = ref.read(_invalidatedOrderIdsProvider.notifier);
  notifier.state = {...notifier.state, orderId};
}

 List<CartItem> _rowsToCartItems(List<Map<String, dynamic>> rows) {
  return CartItem.groupOrderItemRows<Map<String, dynamic>>(
    rows,
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
          round: row['round'] as int? ?? 1,
          discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0,
          discountType: CartItem.discountTypeFromString(
              row['discount_type'] as String?),
        );
      }
      final pMap = row['products'] as Map<String, dynamic>? ?? {};
      final product = Product.fromMap({
        ...pMap,
        'category': '',
        'business_id': pMap['business_id'] ?? '',
      });
      final vMap = row['product_variants'] as Map<String, dynamic>?;
      return CartItem(
        product: product,
        selectedVariant: vMap != null ? ProductVariant.fromMap(vMap) : null,
        quantity: row['quantity'] as int,
        costAtSale: (row['cost_price'] as num?)?.toDouble() ?? 0,
        notes: row['notes'] as String?,
        round: row['round'] as int? ?? 1,
        discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0,
        discountType:
            CartItem.discountTypeFromString(row['discount_type'] as String?),
      );
    },
    buildComponent: (row) {
      final pMap = row['products'] as Map<String, dynamic>? ?? {};
      return PromoComponent(
        promoId: row['promo_id'] as String? ?? '',
        productId: row['product_id'] as String,
        productName: row['product_name'] as String,
        quantity: row['quantity'] as int,
        variantId: row['variant_id'] as String?,
        trackInventory: pMap['track_inventory'] as bool? ?? false,
        sendToKitchen: pMap['send_to_kitchen'] as bool? ?? true,
      );
    },
  );
}

// ── Live / cached order stream ────────────────────────────────────────────────

final localOrdersRevisionProvider = StateProvider<int>((ref) => 0);
final ordersStreamProvider = StreamProvider<List<Order>>((ref) async* {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) {
    yield [];
    return;
  }
  ref.watch(localOrdersRevisionProvider);
  final local = ref.read(localDbServiceProvider);
  // Item cache: avoid re-fetching items for orders that haven't changed.
  final itemCache = <String, List<CartItem>>{};

  // Watch invalidation signals — evict specific orders when voided/updated.
  ref.listen<Set<String>>(_invalidatedOrderIdsProvider, (_, invalidated) {
    if (invalidated.isEmpty) return; // clearing the signal re-fires this listener
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
'*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active, send_to_kitchen), product_variants(id, product_id, name, price_delta, cost_price, stock_quantity, is_active)')
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
                    round: row['round'] as int? ?? 1,
                    discountAmount:
                        (row['discount_amount'] as num?)?.toDouble() ?? 0,
                    discountType: CartItem.discountTypeFromString(
                        row['discount_type'] as String?),
                  );
                }
                final pMap = row['products'] as Map<String, dynamic>? ?? {};
                final product = Product.fromMap({
                  ...pMap,
                  'category': '',
                  'business_id': pMap['business_id'] ?? '',
                });
                final vMap = row['product_variants'] as Map<String, dynamic>?;
                return CartItem(
                  product: product,
                  selectedVariant:
                      vMap != null ? ProductVariant.fromMap(vMap) : null,
                  quantity: row['quantity'] as int,
                  costAtSale: (row['cost_price'] as num?)?.toDouble() ?? 0,
                  notes: row['notes'] as String?,
                  round: row['round'] as int? ?? 1,
                  discountAmount:
                      (row['discount_amount'] as num?)?.toDouble() ?? 0,
                  discountType: CartItem.discountTypeFromString(
                      row['discount_type'] as String?),
                );
              },
              buildComponent: (row) {
                final pMap = row['products'] as Map<String, dynamic>? ?? {};
                return PromoComponent(
                  promoId: row['promo_id'] as String? ?? '',
                  productId: row['product_id'] as String,
                  productName: row['product_name'] as String,
                  quantity: row['quantity'] as int,
                  variantId: row['variant_id'] as String?,
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

        // Orders with queued changes show their local copy until they sync.
        final pendingIds = await local.getOrderIdsWithPendingQueue();
        final unsyncedIds = await local.getUnsyncedOrderIds();
        if (pendingIds.isEmpty && unsyncedIds.isEmpty) return orders;
        final localAll = await local.getOrders(businessId);
        final localById = {for (final o in localAll) o.id: o};
        final remoteIds = orders.map((o) => o.id).toSet();
        final merged = [
          for (final o in orders)
            pendingIds.contains(o.id) ? (localById[o.id] ?? o) : o,
        ];
        final localOnly = localAll.where(
            (o) => unsyncedIds.contains(o.id) && !remoteIds.contains(o.id));
        return [...localOnly, ...merged];
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

class AlreadyPaidException implements Exception {
  @override
  String toString() => 'This order was already paid (possibly on another device).';
}

class AppendResult {
  final int round;
  final bool queued; // true = saved locally, waiting to sync
  const AppendResult({required this.round, required this.queued});
}

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
    String? customerName,
  }) async {
    // One id for the whole attempt, so an online try that fails halfway
    // and the offline fallback refer to the same order (replay is idempotent).
    final orderId = const Uuid().v4();

    if (_isOnline) {
      try {
        return await _placeOnline(
          orderId: orderId,
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
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        debugPrint('[OrderService] placeOnline hit network error, falling back offline: $e');
        _ref.read(isOnlineProvider.notifier).state = false;
      }
    }
    return _placeOffline(
      orderId: orderId,
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

  Future<Order> _placeOnline({
    required String orderId,
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    required double taxRate,
    required double discountAmount,
    double tipAmount = 0.0,
    String? cashierId,
    OrderType orderType = OrderType.walkIn,
    String? customerName,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount + tipAmount;

    final orderRow = await _client
        .from('orders')
        .insert({
          'id': orderId,
          'business_id': businessId,
          'table_id': tableId,
          'cashier_id': cashierId,
          'order_type': tableId != null ? 'walk_in' : orderType.value,
          'customer_name': customerName,
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

    final orderItems = items
        .expand((item) => _withMeta(
            _withVariant(_buildOnlineRows(orderId, item), item), item, 1))
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
    required String orderId,
    required String businessId,
    required List<CartItem> items,
    String? tableId,
    String? notes,
    required double taxRate,
    required double discountAmount,
    double tipAmount = 0.0,
    String? cashierId,
    OrderType orderType = OrderType.walkIn,
    String? customerName,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.total);
    final taxAmount = subtotal * taxRate;
    final totalAmount = subtotal + taxAmount - discountAmount + tipAmount;

    final offlineId = orderId;
    final now = DateTime.now();
    final localOrderNumber = now.millisecondsSinceEpoch;

    final order = Order(
      id: offlineId,
      businessId: businessId,
      tableId: tableId,
      cashierId: cashierId,
      orderNumber: localOrderNumber,
      orderType: tableId != null ? OrderType.walkIn : orderType,
      customerName: customerName,
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
        .expand((i) => _withMeta(_withVariant(_buildOfflineRows(i), i), i, 1))
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
          'customer_name': customerName,
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
    _ref.read(localOrdersRevisionProvider.notifier).state++;

    EventBus.instance.emit(AppEvents.orderPlaced, {
      'order_id': order.id,
      'business_id': businessId,
    });

    return order;
  }

  // ── Update status ───────────────────────────────────────────────────────────


  /// Appends [items] as a new round on an existing unpaid order.
  /// Works offline: writes locally, then syncs now or queues for later.
  Future<AppendResult> appendItems({
    required String orderId,
    required String businessId,
    required List<CartItem> items,
    double taxRate = 0.0,
    bool reopenForKitchen = false,
  }) async {
    var paid = false, cancelled = false, maxRound = 1, checked = false;

    final insertPending = await _local.isOrderPendingSync(orderId);
    if (_isOnline && !insertPending) {
      try {
        final cur = await _client
            .from('orders')
            .select('status, paid_at')
            .eq('id', orderId)
            .single();
        paid = cur['paid_at'] != null;
        cancelled = cur['status'] == 'cancelled';
        final r = await _client
            .from('order_items')
            .select('round')
            .eq('order_id', orderId)
            .order('round', ascending: false)
            .limit(1);
        if ((r as List).isNotEmpty) maxRound = r.first['round'] as int;
        checked = true;
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        _ref.read(isOnlineProvider.notifier).state = false;
      }
    }
    final info = await _local.getOrderAppendInfo(orderId);
    if (!checked) {
      if (info == null) throw Exception('Order not found on this device.');
      paid = info.paid;
      cancelled = info.cancelled;
    }
    // Local may hold rounds the server hasn't received yet.
    if (info != null && info.maxRound > maxRound) maxRound = info.maxRound;
    if (paid) throw Exception('This order is already paid.');
    if (cancelled) throw Exception('This order was cancelled.');

    final round = maxRound + 1;
    final addSubtotal = items.fold<double>(0, (s, i) => s + i.total);
    final addTax = addSubtotal * taxRate;

    final rows = [
      for (final item in items)
        ..._withMeta(
            _withVariant(_buildOnlineRows(orderId, item), item), item, round),
    ].map((r) => {...r, 'id': const Uuid().v4()}).toList();

    // 1. Local first, so the app shows it immediately and Pay sees it.
    await _local.appendOrderItems(
      orderId: orderId,
      items: items.map((i) => i.withRound(round)).toList(),
      addSubtotal: addSubtotal,
      addTax: addTax,
      reopen: reopenForKitchen,
    );
    await _deductInventory(businessId, items);

    // 2. Server: sync now if possible, otherwise queue (same code path).
    final payload = {
      'order_id': orderId,
      'business_id': businessId,
      'items': rows,
      'tax_rate': taxRate,
      'reopen_for_kitchen': reopenForKitchen,
    };
    var queued = true;
    if (_isOnline && !insertPending) {
      try {
        await _syncQueue.replayAppendOrderItems(payload);
        queued = false;
      } catch (e) {
        debugPrint('[OrderService] appendItems online failed, queuing: $e');
      }
    }
    if (queued) {
      await _syncQueue.enqueue(
        operation: 'append_order_items',
        tableName: 'order_items',
        recordId: orderId,
        payload: payload,
      );
    }

    invalidateOrderCache(_ref, orderId);
    _ref.invalidate(productListProvider);
    _ref.read(localOrdersRevisionProvider.notifier).state++;
    EventBus.instance.emit(AppEvents.orderStatusChanged, {'order_id': orderId});
    return AppendResult(round: round, queued: queued);
  }


  /// Saves the discount/tip chosen at checkout onto an existing order so the
  /// order, receipt and reports all show what was actually charged.
  Future<void> applyAdjustments({
    required String orderId,
    required double discount,
    required double tip,
  }) async {
    await _local.updateOrderAdjustments(
        orderId: orderId, discount: discount, tip: tip);
    final payload = {'order_id': orderId, 'discount': discount, 'tip': tip};
    var queued = true;
    final insertPending = await _local.isOrderPendingSync(orderId);
    if (_isOnline && !insertPending) {
      try {
        await _syncQueue.replayOrderAdjustments(payload);
        queued = false;
      } catch (e) {
        debugPrint('[OrderService] applyAdjustments online failed, queuing: $e');
      }
    }
    if (queued) {
      await _syncQueue.enqueue(
        operation: 'update_order_adjustments',
        tableName: 'orders',
        recordId: orderId,
        payload: payload,
      );
    }
    _ref.read(localOrdersRevisionProvider.notifier).state++;
  }

Future<void> updateStatus(String orderId, OrderStatus status) async {
    await _local.markOrderStatus(orderId, status);
    final insertPending = await _local.isOrderPendingSync(orderId);

    if (_isOnline && !insertPending) {
      try {
        await _client.from('orders').update({
          'status': status.value,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);
        EventBus.instance.emit(AppEvents.orderStatusChanged,
            {'order_id': orderId, 'status': status.value});
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
    _ref.read(localOrdersRevisionProvider.notifier).state++;
    EventBus.instance.emit(AppEvents.orderStatusChanged,
        {'order_id': orderId, 'status': status.value});
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

    final insertPending = await _local.isOrderPendingSync(orderId);
    if (_isOnline && !insertPending) {
      try {
        final updated = await _client
            .from('orders')
            .update({
              ...payload,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderId)
            .isFilter('paid_at', null) // only if nobody paid it first
            .select('id');
        if ((updated as List).isEmpty) throw AlreadyPaidException();

        await _local.updateOrderPayment(
          orderId: orderId,
          method: method,
          amountTendered: amountTendered,
          changeAmount: changeAmount,
          referenceNumber: referenceNumber,
        );
        return;
      } catch (e) {
        if (e is AlreadyPaidException) rethrow;
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

    final insertPending = await _local.isOrderPendingSync(orderId);
    if (_isOnline && !insertPending) {
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
      variantId: variantId,
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
        // variantId is non-null when the voided item was a variant sale.
        // Re-read stock so a stale snapshot can't overwrite newer sales.
        if (variantId != null) {
          final fv = (await _local.getVariantsForProduct(productId))
              .where((v) => v.id == variantId)
              .firstOrNull;
          currentStock = fv?.stockQuantity ?? currentStock;
        } else {
          final fp = (await _local.getProducts(businessId))
              .where((p) => p.id == productId)
              .firstOrNull;
          currentStock = fp?.stockQuantity ?? currentStock;
        }
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
            .insert({
              ...voidRecord.toMap(),
              if (variantId != null) 'variant_id': variantId,
            });

        // Remove item from Supabase order_items
        var find = _client
            .from('order_items')
            .select('id')
            .eq('order_id', orderId)
            .eq('product_id', productId);
        if (variantId != null) find = find.eq('variant_id', variantId);
        final target = await find.limit(1).maybeSingle();
        if (target != null) {
          await _client
              .from('order_items')
              .delete()
              .eq('id', target['id'] as String);
        }

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
        if (variantId != null) 'variant_id': variantId,
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
            for (final e in localRow.entries)
              if (e.key != 'synced') e.key: e.value,
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
    // If this order has queued changes (e.g. a round that hasn't synced),
    // the local copy is newer than the server's.
    final queued = await _local.getOrderIdsWithPendingQueue();
    final unsynced = await _local.isOrderPendingSync(orderId);
    final preferLocal = queued.contains(orderId) || unsynced;
    if (_isOnline && !preferLocal) {
      try {
        final orderRow = await _client
            .from('orders')
            .select()
            .eq('id', orderId)
            .single();

                final itemRows = await _client
            .from('order_items')
            .select(
'*, products(id, name, price, track_inventory, stock_quantity, business_id, is_available, is_active, send_to_kitchen), product_variants(id, product_id, name, price_delta, cost_price, stock_quantity, is_active)')
            .eq('order_id', orderId);

        final cartItems =
            _rowsToCartItems((itemRows as List).cast<Map<String, dynamic>>());

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

  /// Stamps round on every row and the per-item discount on the line's main
  /// row (index 0: the plain item or the promo header).
  List<Map<String, dynamic>> _withMeta(
      List<Map<String, dynamic>> rows, CartItem item, int round) {
    return [
      for (var i = 0; i < rows.length; i++)
        {
          ...rows[i],
          'round': round,
          if (i == 0) 'discount_amount': item.discountAmount,
          if (i == 0) 'discount_type': item.discountType.name,
        },
    ];
  }

  /// Adds variant_id to the rows built above: the plain item's chosen
  /// variant, or each promo component's variant (row 0 is the promo header).
  List<Map<String, dynamic>> _withVariant(
      List<Map<String, dynamic>> rows, CartItem item) {
    if (item.isPromo) {
      final comps = item.promoComponents!;
      return [
        for (var i = 0; i < rows.length; i++)
          i == 0
              ? rows[i]
              : {...rows[i], 'variant_id': comps[i - 1].variantId},
      ];
    }
    return [
      {...rows.first, 'variant_id': item.selectedVariant?.id},
    ];
  }

  // ── Inventory deduction─────────────────────────────────────────────────────

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