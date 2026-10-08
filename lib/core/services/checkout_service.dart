// lib/core/services/checkout_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../models/order_payment.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import '../providers/order_provider.dart';
import '../providers/staff_provider.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../../features/auth/auth_provider.dart';
import '../providers/app_context_provider.dart';
import '../../features/tables/table_provider.dart';
import '../../features/settings/settings_provider.dart';
import 'receipt_service.dart';
import 'thermal_print_service.dart';
import '../services/sync_queue_service.dart';

final checkoutServiceProvider = Provider<CheckoutService>((ref) {
  return CheckoutService(ref);
});


class CheckoutService {
  final Ref _ref;
  CheckoutService(this._ref);

  bool get _isOnline => _ref.read(isOnlineProvider);

  Future<String?> resolveTableUuid({
    required String businessId,
    required String tableNumber,
  }) async {
    final localUuid = _ref.read(tableProvider).uuidForTable(tableNumber);
    if (localUuid != null) return localUuid;
    if (!_isOnline) return null;

    final client = _ref.read(supabaseClientProvider);
    final row = await client
        .from('restaurant_tables')
        .select('id')
        .eq('business_id', businessId)
        .eq('table_number', tableNumber.toString())
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<CheckoutResult> placeOrder({
    required BuildContext context,
    required bool payNow,
    required bool isRestaurant,
    required bool hasKitchen,
    required String? existingOrderId,
    required PaymentMethod paymentMethod,
    required double tendered,
    required double change,
    List<PaymentSplitInput>? splitPayments,
    required double subtotal,
    required List<CartItem> items,
    required double discountAmount,
    double tipAmount = 0,
    String? referenceNumber,
    String? tableNumber,
    String? roomName,
    double splitChangeAmount = 0,
    String? customerName,
  }) async {
    final effectiveSplitPayments = splitPayments ?? const <PaymentSplitInput>[];
    final isSplit = effectiveSplitPayments.isNotEmpty;
    final businessId = _ref.read(activeBusinessIdProvider);
    if (businessId == null) {
      return CheckoutResult.error('No business profile found.');
    }
    final profile = _ref.read(profileProvider).asData?.value;

    // Validate reference number for non-cash, non-credit payments.
    // Split payments carry their own per-leg reference numbers (validated
    // by the caller before this is invoked), so this check is skipped
    // entirely when splitPayments is provided.
    if (payNow &&
        !isSplit &&
        paymentMethod != PaymentMethod.cash &&
        paymentMethod != PaymentMethod.credit &&
        (referenceNumber == null || referenceNumber.trim().isEmpty)) {
      return CheckoutResult.error(
        'Please enter the ${_methodLabel(paymentMethod)} reference number.',
      );
    }

    if (payNow && isSplit) {
      final applied =
          effectiveSplitPayments.fold<double>(0, (s, p) => s + p.amount);
      if (((applied - subtotal) * 100).round().abs() > 1) {
        return CheckoutResult.error(
          'Split payments (₱${applied.toStringAsFixed(2)}) do not match '
          'the amount due (₱${subtotal.toStringAsFixed(2)}).',
        );
      }
    }

    final service = _ref.read(orderServiceProvider);
    final local = _ref.read(localDbServiceProvider);
    final selectedTableName = _ref.read(tableProvider).selectedTableName;

    // Read tax rate from business config
    final config = _ref.read(businessConfigProvider);
    final taxRate = config?.taxRate ?? 0.0;

    // Resolve cashier ID from active staff session
    final activeStaff = _ref.read(activeStaffProvider);
    final cashierId = activeStaff?.id;
    debugPrint('[Checkout] activeStaff: ${activeStaff?.name}, cashierId: $cashierId');

    Order order;

    if (existingOrderId != null) {
      order = await service.fetchOrderWithItems(existingOrderId);
      if (order.paidAt != null) {
        return CheckoutResult.error('This order is already paid.');
      }
      if (order.status == OrderStatus.cancelled) {
        return CheckoutResult.error('This order was cancelled.');
      }
      // Save the discount/tip shown in the dialog onto the order itself.
      if ((discountAmount - order.discountAmount).abs() > 0.005 ||
          (tipAmount - order.tipAmount).abs() > 0.005) {
        await service.applyAdjustments(
            orderId: order.id, discount: discountAmount, tip: tipAmount);
        order = order.copyWith(
          discountAmount: discountAmount,
          tipAmount: tipAmount,
          totalAmount:
              order.subtotal + order.taxAmount - discountAmount + tipAmount,
        );
      }
    } else {
      // ── Stock validation ────────────────────────────────────────────────
      if (_isOnline) {
        final client = _ref.read(supabaseClientProvider);
        for (final item in items) {
          if (item.isPromo) {
            final err = await _checkPromoStockOnline(client, local, businessId, item);
            if (err != null) return CheckoutResult.error(err);
            continue;
          }
          if (item.product.isCustom) continue;
          if (!item.product.trackInventory) continue;
          if (item.selectedVariant != null) {
            final err = await _checkVariantStock(item);
            if (err != null) return CheckoutResult.error(err);
            continue;
          }
          try {
            final row = await client
                .from('products')
                .select('stock_quantity, name')
                .eq('id', item.product.id)
                .single();
            final available = row['stock_quantity'] as int? ?? 0;
            if (item.quantity > available) {
              return CheckoutResult.error(
                '${row['name']} only has $available in stock '
                '(you have ${item.quantity} in cart).',
              );
            }
          } catch (e) {
            debugPrint('[Checkout] Stock check failed, using local cache: $e');
            final cached = await local.getProducts(businessId);
            final p =
                cached.where((p) => p.id == item.product.id).firstOrNull;
            if (p != null &&
                p.trackInventory &&
                item.quantity > p.stockQuantity) {
              return CheckoutResult.error(
                '${p.name} only has ${p.stockQuantity} in stock '
                '(you have ${item.quantity} in cart).',
              );
            }
          }
        }
      } else {
        final cached = await local.getProducts(businessId);
        for (final item in items) {
          if (item.isPromo) {
            final err = await _checkPromoStockLocal(cached, item);
            if (err != null) return CheckoutResult.error(err);
            continue;
          }
          if (item.product.isCustom) continue;
          if (!item.product.trackInventory) continue;
          if (item.selectedVariant != null) {
            final err = await _checkVariantStock(item);
            if (err != null) return CheckoutResult.error(err);
            continue;
          }
          final p =
              cached.where((p) => p.id == item.product.id).firstOrNull;
          if (p != null && item.quantity > p.stockQuantity) {
            return CheckoutResult.error(
              '${p.name} only has ${p.stockQuantity} in stock '
              '(you have ${item.quantity} in cart).',
            );
          }
        }
      }

      // ── Table resolution ────────────────────────────────────────────────
      String? tableUuid;
      if (isRestaurant && selectedTableName != null) {
        tableUuid = await resolveTableUuid(
          businessId: businessId,
          tableNumber: selectedTableName,
        );
        if (tableUuid == null && _isOnline) {
          return CheckoutResult.error(
              'Could not find Table $selectedTableName.');
        }
      }

      final orderType = _ref.read(cartProvider.notifier).orderType;
      order = await service.placeOrder(
        businessId: businessId,
        items: items,
        tableId: tableUuid,
        notes: null,
        cashierId: cashierId,
        taxRate: taxRate,
        discountAmount: discountAmount,
        tipAmount: tipAmount,
        orderType: orderType,
        customerName: customerName,
      );
      final kitchenItems = items.where((i) => i.product.sendToKitchen).toList();

      if (hasKitchen && kitchenItems.isNotEmpty) {
        if (_isOnline) {
          try {
            final client = _ref.read(supabaseClientProvider);
            await client.from('kitchen_tickets').insert({
              'order_id': order.id,
              'business_id': businessId,
              'status': 'queued',
            });
          } catch (e) {
            debugPrint('[Checkout] Kitchen ticket online failed, queuing: $e');
            await _ref.read(syncQueueServiceProvider).enqueue(
              operation: 'insert_kitchen_ticket',
              tableName: 'kitchen_tickets',
              recordId: order.id,
              payload: {
                'order_id': order.id,
                'business_id': businessId,
                'status': 'queued',
              },
            );
          }
        } else {
          await _ref.read(syncQueueServiceProvider).enqueue(
            operation: 'insert_kitchen_ticket',
            tableName: 'kitchen_tickets',
            recordId: order.id,
            payload: {
              'order_id': order.id,
              'business_id': businessId,
              'status': 'queued',
            },
          );
        }
      }

      if (isRestaurant && selectedTableName != null) {
        _ref
            .read(tableProvider.notifier)
            .occupyTable(selectedTableName, order.id);
      }

      if (!payNow) {
        _ref.read(cartProvider.notifier).clear();
        return CheckoutResult.sentToKitchen(order);
      }
    }

    // ── Process payment ─────────────────────────────────────────────────────
    final actualTendered = isSplit
        ? effectiveSplitPayments.fold<double>(0, (s, p) => s + p.amount) + splitChangeAmount
        : (paymentMethod == PaymentMethod.cash ? tendered : subtotal);
    final actualChange = isSplit
        ? splitChangeAmount
        : (paymentMethod == PaymentMethod.cash ? change : 0.0);
    final cleanRef =
        referenceNumber?.trim().isEmpty == true
            ? null
            : referenceNumber?.trim();

    if (isSplit) {
      await service.processSplitPayment(
        orderId: order.id,
        businessId: businessId,
        payments: effectiveSplitPayments,
        changeAmount: splitChangeAmount,
      );
    } else {
      await service.processPayment(
        orderId: order.id,
        method: paymentMethod,
        amountTendered: actualTendered,
        changeAmount: actualChange,
        referenceNumber: cleanRef,
      );
    }

    if (!hasKitchen || !order.items.any((i) => i.hasKitchenWork)) {
      await service.updateStatus(order.id, OrderStatus.completed);
    }

    // ── Receipt ─────────────────────────────────────────────────────────────
    // Use the already-loaded business from profileProvider — avoids a
    // redundant Supabase round-trip on every payment (#14).
    final business = profile!.business;
    String businessName = business?.name ?? 'My Business';
    String? businessAddress = business?.address;
    String? businessPhone = business?.phone;
    String? businessEmail = business?.email;

    final paidOrder = order.copyWith(
      items: mergeForReceipt(order.items),
      paymentMethod: paymentMethod,
      amountTendered: actualTendered,
      changeAmount: actualChange,
      referenceNumber: cleanRef,
      isSplitPayment: isSplit,
    );

    await _ref.read(receiptServiceProvider).createReceipt(
      order: paidOrder,
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessEmail: businessEmail,
      taxRate: taxRate,
      issuedBy: profile.id,
      footerText: isRestaurant
          ? 'Thank you for dining with us!'
          : 'Thank you for shopping with us!',
    );

    // ✅ NEW: Auto open cash drawer — also opens when a split payment
    // includes a cash leg, not just when cash is the sole method.
    final hasCashLeg = isSplit
        ? effectiveSplitPayments.any((p) => p.method == PaymentMethod.cash)
        : paymentMethod == PaymentMethod.cash;
    if (hasCashLeg) {
      try {
        await ThermalPrintService.openCashDrawer();
      } catch (e) {
        debugPrint('[Checkout] Cash drawer failed: $e');
      }
    }

    // Auto print receipt
    try {
      await ThermalPrintService.printReceipt(
        order: paidOrder,
        tendered: actualTendered,
        change: actualChange,
        businessName: businessName,
        tableNumber: tableNumber,
        roomName: roomName,
      );
    } catch (e) {
      debugPrint('[Checkout] Print failed: $e');
    }

    _ref.read(cartProvider.notifier).clear();
    return CheckoutResult.paid(
      order: paidOrder,
      tendered: actualTendered,
      change: actualChange,
    );
  }

    Future<CheckoutResult> addToTab({
    required String orderId,
    required bool hasKitchen,
    required List<CartItem> items,
  }) async {
    final businessId = _ref.read(activeBusinessIdProvider);
    if (businessId == null) {
      return CheckoutResult.error('No business profile found.');
    }
    if (items.isEmpty) return CheckoutResult.error('Cart is empty.');
    try {
      String? stockErr;
      if (_isOnline) {
        try {
          stockErr = await _validateStockOnline(businessId, items);
        } catch (e) {
          if (!isNetworkError(e)) rethrow;
          stockErr = await _validateStockLocal(businessId, items);
        }
      } else {
        stockErr = await _validateStockLocal(businessId, items);
      }
      if (stockErr != null) return CheckoutResult.error(stockErr);

      final taxRate = _ref.read(businessConfigProvider)?.taxRate ?? 0.0;
      final sendToKitchen = hasKitchen && items.any((i) => i.hasKitchenWork);

      final res = await _ref.read(orderServiceProvider).appendItems(
            orderId: orderId,
            businessId: businessId,
            items: items,
            taxRate: taxRate,
            reopenForKitchen: sendToKitchen,
          );

      if (sendToKitchen) {
        await _createKitchenTicket(orderId, businessId, res.round);
      }

      _ref.read(cartProvider.notifier).clear();
      return CheckoutResult.addedToTab(round: res.round, pendingSync: res.queued);
    } catch (e) {
      return CheckoutResult.error('Could not add items: $e');
    }
  }

  Future<void> _createKitchenTicket(
      String orderId, String businessId, int round) async {
    final payload = {
      'order_id': orderId,
      'business_id': businessId,
      'status': 'queued',
      'round': round,
    };
    if (_isOnline) {
      try {
        await _ref.read(supabaseClientProvider).from('kitchen_tickets').insert(payload);
        return;
      } catch (e) {
        debugPrint('[Checkout] Round ticket online failed, queuing: $e');
      }
    }
    await _ref.read(syncQueueServiceProvider).enqueue(
          operation: 'insert_kitchen_ticket',
          tableName: 'kitchen_tickets',
          recordId: orderId,
          payload: payload,
        );
  }

  Future<String?> _validateStockLocal(
      String businessId, List<CartItem> items) async {
    final cached =
        await _ref.read(localDbServiceProvider).getProducts(businessId);
    for (final item in items) {
      if (item.isPromo) {
        final e = await _checkPromoStockLocal(cached, item);
        if (e != null) return e;
        continue;
      }
      if (item.product.isCustom || !item.product.trackInventory) continue;
      if (item.selectedVariant != null) {
        final e = await _checkVariantStock(item);
        if (e != null) return e;
        continue;
      }
      final p = cached.where((p) => p.id == item.product.id).firstOrNull;
      if (p != null && item.quantity > p.stockQuantity) {
        return '${p.name} only has ${p.stockQuantity} in stock '
            '(you have ${item.quantity} in cart).';
      }
    }
    return null;
  }

  Future<String?> _validateStockOnline(
      String businessId, List<CartItem> items) async {
    final client = _ref.read(supabaseClientProvider);
    final local = _ref.read(localDbServiceProvider);
    for (final item in items) {
      if (item.isPromo) {
        final e = await _checkPromoStockOnline(client, local, businessId, item);
        if (e != null) return e;
        continue;
      }
      if (item.product.isCustom || !item.product.trackInventory) continue;
      if (item.selectedVariant != null) {
        final e = await _checkVariantStock(item);
        if (e != null) return e;
        continue;
      }
      final row = await client
          .from('products')
          .select('stock_quantity, name')
          .eq('id', item.product.id)
          .single();
      final available = row['stock_quantity'] as int? ?? 0;
      if (item.quantity > available) {
        return '${row['name']} only has $available in stock '
            '(you have ${item.quantity} in cart).';
      }
    }
    return null;
  }

  Future<int?> _variantStockLeft(String productId, String variantId) async {
    if (_isOnline) {
      try {
        final row = await _ref
            .read(supabaseClientProvider)
            .from('product_variants')
            .select('stock_quantity')
            .eq('id', variantId)
            .single();
        return row['stock_quantity'] as int? ?? 0;
      } catch (_) {}
    }
    final vs = await _ref
        .read(localDbServiceProvider)
        .getVariantsForProduct(productId);
    return vs.where((v) => v.id == variantId).firstOrNull?.stockQuantity;
  }

  Future<String?> _checkVariantStock(CartItem item) async {
    final id = item.selectedVariant!.id;
    int? available;
    var name = item.selectedVariant!.name;

    if (_isOnline) {
      try {
        final row = await _ref
            .read(supabaseClientProvider)
            .from('product_variants')
            .select('stock_quantity, name')
            .eq('id', id)
            .single();
        available = row['stock_quantity'] as int? ?? 0;
        name = row['name'] as String? ?? name;
      } catch (_) {}
    }
    if (available == null) {
      final vs = await _ref
          .read(localDbServiceProvider)
          .getVariantsForProduct(item.product.id);
      final v = vs.where((v) => v.id == id).firstOrNull;
      if (v == null) return null;
      available = v.stockQuantity;
      name = v.name;
    }
    if (item.quantity > available) {
      return '${item.product.name} ($name) only has $available in stock '
          '(you have ${item.quantity} in cart).';
    }
    return null;
  }

  String _methodLabel(PaymentMethod method) => switch (method) {
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.maya => 'Maya',
        PaymentMethod.card => 'card',
        PaymentMethod.cash => 'cash',
        PaymentMethod.credit => 'credit',
      };

  Future<String?> _checkPromoStockOnline(
      dynamic client, LocalDbService local, String businessId, CartItem item) async {
    for (final c in item.promoComponents!) {
      if (!c.trackInventory) continue;
      final needed = c.quantity * item.quantity;
      if (c.variantId != null) {
        final left = await _variantStockLeft(c.productId, c.variantId!);
        if (left != null && needed > left) {
          return '${c.productName}${c.variantName != null ? ' (${c.variantName})' : ''} only has $left in stock '
              '(this order needs $needed for "${item.product.name}").';
        }
        continue;
      }
      try {
        final row = await client
            .from('products')
            .select('stock_quantity, name')
            .eq('id', c.productId)
            .single();
        final available = row['stock_quantity'] as int? ?? 0;
        if (needed > available) {
          return '${row['name']} only has $available in stock '
              '(this order needs $needed for "${item.product.name}").';
        }
      } catch (e) {
        debugPrint('[Checkout] Promo stock check failed, using local cache: $e');
        final cached = await local.getProducts(businessId);
        final p = cached.where((p) => p.id == c.productId).firstOrNull;
        if (p != null && needed > p.stockQuantity) {
          return '${p.name} only has ${p.stockQuantity} in stock '
              '(this order needs $needed for "${item.product.name}").';
        }
      }
    }
    return null;
  }

  Future<String?> _checkPromoStockLocal(List cached, CartItem item) async {
    for (final c in item.promoComponents!) {
      if (!c.trackInventory) continue;
      final needed = c.quantity * item.quantity;
      if (c.variantId != null) {
        final left = await _variantStockLeft(c.productId, c.variantId!);
        if (left != null && needed > left) {
          return '${c.productName}${c.variantName != null ? ' (${c.variantName})' : ''} only has $left in stock '
              '(this order needs $needed for "${item.product.name}").';
        }
        continue;
      }
      final p = cached.where((p) => p.id == c.productId).firstOrNull;
      if (p != null && needed > p.stockQuantity) {
        return '${p.name} only has ${p.stockQuantity} in stock '
            '(this order needs $needed for "${item.product.name}").';
      }
    }
    return null;
  }
}


// ── Result type ───────────────────────────────────────────────────────────────

enum CheckoutStatus { paid, sentToKitchen, error }

class CheckoutResult {
  final CheckoutStatus status;
  final Order? order;
  final double tendered;
  final double change;
  final String? errorMessage;
  final bool pendingSync;
  final int? round;

  const CheckoutResult._({
    required this.status,
    this.order,
    this.tendered = 0,
    this.change = 0,
    this.errorMessage,
    this.pendingSync = false,
    this.round,
  });

  factory CheckoutResult.paid({
    required Order order,
    required double tendered,
    required double change,
  }) =>
      CheckoutResult._(
        status: CheckoutStatus.paid,
        order: order,
        tendered: tendered,
        change: change,
      );

  factory CheckoutResult.sentToKitchen(Order order) => CheckoutResult._(
        status: CheckoutStatus.sentToKitchen,
        order: order,
      );

  factory CheckoutResult.addedToTab({
    required int round,
    required bool pendingSync,
  }) =>
      CheckoutResult._(
        status: CheckoutStatus.sentToKitchen,
        round: round,
        pendingSync: pendingSync,
      );

  factory CheckoutResult.error(String message) => CheckoutResult._(
        status: CheckoutStatus.error,
        errorMessage: message,
      );
}