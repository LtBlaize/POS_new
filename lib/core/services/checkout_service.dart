// lib/core/services/checkout_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import '../providers/order_provider.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/tables/table_provider.dart';
import 'reciept_service.dart';

final checkoutServiceProvider = Provider<CheckoutService>((ref) {
  return CheckoutService(ref);
});

class CheckoutService {
  final Ref _ref;
  CheckoutService(this._ref);

  /// Resolves the actual UUID for the selected table number.
  Future<String?> resolveTableUuid({
    required String businessId,
    required int tableNumber,
  }) async {
    final localUuid =
        _ref.read(tableProvider).uuidForTable(tableNumber);
    if (localUuid != null) return localUuid;

    final client = _ref.read(supabaseClientProvider);
    final row = await client
        .from('restaurant_tables')
        .select('id')
        .eq('business_id', businessId)
        .eq('table_number', tableNumber.toString())
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Places (or pays) an order.
  ///
  /// [payNow]         – false → send to kitchen only (pay later).
  /// [isRestaurant]   – whether the business has kitchen/tables features.
  /// [hasKitchen]     – whether the kitchen feature is enabled.
  /// [existingOrderId]– non-null when paying an already-placed order.
  /// [paymentMethod]  – selected payment method.
  /// [tendered]       – cash amount handed over (cash only).
  /// [change]         – change to return (cash only).
  /// [subtotal]       – cart subtotal (used for non-cash tendered).
  Future<CheckoutResult> placeOrder({
    required bool payNow,
    required bool isRestaurant,
    required bool hasKitchen,
    required String? existingOrderId,
    required PaymentMethod paymentMethod,
    required double tendered,
    required double change,
    required double subtotal,
    required List<CartItem> items,
  }) async {
    debugPrint(
        '🏪 isRestaurant: $isRestaurant, hasKitchen: $hasKitchen, existingOrderId: $existingOrderId');

    final profile = _ref.read(profileProvider).asData?.value;
    if (profile?.businessId == null) {
      return CheckoutResult.error('No business profile found.');
    }

    final service = _ref.read(orderServiceProvider);
    final selectedTableNumber =
        _ref.read(tableProvider).selectedTableNumber;
    final client = _ref.read(supabaseClientProvider);

    Order order;

    if (existingOrderId != null) {
      // ── Paying an existing order ──────────────────────────────────────
      // Kitchen ticket was already created when order was sent to kitchen
      order = await service.fetchOrderWithItems(existingOrderId);
    } else {
      // ── New order ─────────────────────────────────────────────────────
      String? tableUuid;
      if (isRestaurant && selectedTableNumber != null) {
        tableUuid = await resolveTableUuid(
          businessId: profile!.businessId!,
          tableNumber: selectedTableNumber,
        );
        if (tableUuid == null) {
          return CheckoutResult.error(
              'Could not find Table $selectedTableNumber.');
        }
      }
      // ── Stock validation before placing order ─────────────────────────────
for (final item in items) {
  if (!item.product.trackInventory) continue;

  final row = await client
      .from('products')
      .select('stock_quantity, name')
      .eq('id', item.product.id)
      .single();

  final available = row['stock_quantity'] as int? ?? 0;
  if (item.quantity > available) {
    return CheckoutResult.error(
      '${row['name']} only has $available in stock (you have ${item.quantity} in cart).',
    );
  }
}
// ─────────────────────────────────────────────────────────────────────
      order = await service.placeOrder(
        businessId: profile!.businessId!,
        items: items,
        tableId: tableUuid,
        notes: null,
      );

      if (hasKitchen) {
        await client.from('kitchen_tickets').insert({
          'order_id': order.id,
          'business_id': profile.businessId,
          'status': 'queued',
         
        });
        debugPrint('✅ Kitchen ticket created for new order ${order.id}');
      }

      if (isRestaurant && selectedTableNumber != null) {
        _ref
            .read(tableProvider.notifier)
            .occupyTable(selectedTableNumber, order.id);
      }

      if (!payNow) {
        _ref.read(cartProvider.notifier).clear();
        return CheckoutResult.sentToKitchen(order);
      }
    }

    // ── Process payment ───────────────────────────────────────────────
    final actualTendered =
        paymentMethod == PaymentMethod.cash ? tendered : subtotal;
    final actualChange =
        paymentMethod == PaymentMethod.cash ? change : 0.0;

    await service.processPayment(
      orderId: order.id,
      method: paymentMethod,
      amountTendered: actualTendered,
      changeAmount: actualChange,
    );
    // ← add this
    if (!hasKitchen) {
      await service.updateStatus(order.id, OrderStatus.completed);
    }

    final businessRow = await client
        .from('businesses')
        .select('name, address, phone, email')
        .eq('id', profile!.businessId!)
        .maybeSingle();

    await _ref.read(receiptServiceProvider).createReceipt(
          order: order.copyWith(
            paymentMethod: paymentMethod,
            amountTendered: actualTendered,
            changeAmount: actualChange,
          ),
          businessName: businessRow?['name'] as String? ?? 'My Business',
          businessAddress: businessRow?['address'] as String?,
          businessPhone: businessRow?['phone'] as String?,
          businessEmail: businessRow?['email'] as String?,
          taxRate: 0.12,
          issuedBy: profile.id,
          footerText: isRestaurant
              ? 'Thank you for dining with us!'
              : 'Thank you for shopping with us!',
        );

    _ref.read(cartProvider.notifier).clear();

    return CheckoutResult.paid(
      order: order.copyWith(
        paymentMethod: paymentMethod,
        amountTendered: actualTendered,
        changeAmount: actualChange,
      ),
      tendered: actualTendered,
      change: actualChange,
    );
  }
}

// ── Result type ──────────────────────────────────────────────────────────────

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