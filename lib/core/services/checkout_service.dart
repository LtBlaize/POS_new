// lib/core/services/checkout_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
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
    required double subtotal,
    required List<CartItem> items,
    required double discountAmount,
    double tipAmount = 0,
    String? referenceNumber,
    String? tableNumber,
    String? roomName,
  }) async {
    final businessId = _ref.read(activeBusinessIdProvider);
    if (businessId == null) {
      return CheckoutResult.error('No business profile found.');
    }
    final profile = _ref.read(profileProvider).asData?.value;

    // Validate reference number for non-cash, non-credit payments
    if (payNow &&
        paymentMethod != PaymentMethod.cash &&
        paymentMethod != PaymentMethod.credit &&
        (referenceNumber == null || referenceNumber.trim().isEmpty)) {
      return CheckoutResult.error(
        'Please enter the ${_methodLabel(paymentMethod)} reference number.',
      );
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
    } else {
      // ── Stock validation ────────────────────────────────────────────────
      if (_isOnline) {
        final client = _ref.read(supabaseClientProvider);
        for (final item in items) {
          if (item.product.isCustom) continue;
          if (!item.product.trackInventory) continue;
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
          if (item.product.isCustom) continue;
          if (!item.product.trackInventory) continue;
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
    final actualTendered =
        paymentMethod == PaymentMethod.cash ? tendered : subtotal;
    final actualChange =
        paymentMethod == PaymentMethod.cash ? change : 0.0;
    final cleanRef =
        referenceNumber?.trim().isEmpty == true
            ? null
            : referenceNumber?.trim();

    await service.processPayment(
      orderId: order.id,
      method: paymentMethod,
      amountTendered: actualTendered,
      changeAmount: actualChange,
      referenceNumber: cleanRef,
    );

    if (!hasKitchen) {
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
      paymentMethod: paymentMethod,
      amountTendered: actualTendered,
      changeAmount: actualChange,
      referenceNumber: cleanRef,
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

    // ✅ NEW: Auto open cash drawer
    if (paymentMethod == PaymentMethod.cash) {
      try {
        await ThermalPrintService.openCashDrawer();
      } catch (e) {
        debugPrint('[Checkout] Cash drawer failed: $e');
      }
    }

    // ✅ NEW: Auto print receipt
    // ✅ Auto print receipt
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

  String _methodLabel(PaymentMethod method) => switch (method) {
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.maya => 'Maya',
        PaymentMethod.card => 'card',
        PaymentMethod.cash => 'cash',
        PaymentMethod.credit => 'credit',
      };
}


// ── Result type ───────────────────────────────────────────────────────────────

enum CheckoutStatus { paid, sentToKitchen, error }

class CheckoutResult {
  final CheckoutStatus status;
  final Order? order;
  final double tendered;
  final double change;
  final String? errorMessage;

  const CheckoutResult._({
    required this.status,
    this.order,
    this.tendered = 0,
    this.change = 0,
    this.errorMessage,
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

  factory CheckoutResult.error(String message) => CheckoutResult._(
        status: CheckoutStatus.error,
        errorMessage: message,
      );

      
}