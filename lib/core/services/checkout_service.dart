import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import '../providers/order_provider.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/tables/table_provider.dart';
import 'reciept_service.dart';

final checkoutServiceProvider = Provider<CheckoutService>((ref) {
  return CheckoutService(ref);
});

class CheckoutService {
  final Ref _ref;
  CheckoutService(this._ref);

  bool get _isOnline => _ref.read(isOnlineProvider);

  Future<String?> resolveTableUuid({
    required String businessId,
    required int tableNumber,
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
    final profile = _ref.read(profileProvider).asData?.value;
    if (profile?.businessId == null) {
      return CheckoutResult.error('No business profile found.');
    }

    final service = _ref.read(orderServiceProvider);
    final local = _ref.read(localDbServiceProvider);
    final selectedTableNumber = _ref.read(tableProvider).selectedTableNumber;

    Order order;

    if (existingOrderId != null) {
      order = await service.fetchOrderWithItems(existingOrderId);
    } else {
      // ── Stock validation ──────────────────────────────────────────────
      // Online: validate against Supabase (most accurate)
      // Offline: validate against local SQLite cache
      if (_isOnline) {
        final client = _ref.read(supabaseClientProvider);
        for (final item in items) {
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
            // Fall through to local check below
            final cached = await local.getProducts(profile!.businessId!);
            final p = cached.where((p) => p.id == item.product.id).firstOrNull;
            if (p != null && p.trackInventory && item.quantity > p.stockQuantity) {
              return CheckoutResult.error(
                '${p.name} only has ${p.stockQuantity} in stock '
                '(you have ${item.quantity} in cart).',
              );
            }
          }
        }
      } else {
        // Offline: use SQLite cache for validation
        final cached = await local.getProducts(profile!.businessId!);
        for (final item in items) {
          if (!item.product.trackInventory) continue;
          final p = cached.where((p) => p.id == item.product.id).firstOrNull;
          if (p != null && item.quantity > p.stockQuantity) {
            return CheckoutResult.error(
              '${p.name} only has ${p.stockQuantity} in stock '
              '(you have ${item.quantity} in cart).',
            );
          }
        }
      }

      // ── Table resolution ──────────────────────────────────────────────
      String? tableUuid;
      if (isRestaurant && selectedTableNumber != null) {
        tableUuid = await resolveTableUuid(
          businessId: profile!.businessId!,
          tableNumber: selectedTableNumber,
        );
        if (tableUuid == null && _isOnline) {
          return CheckoutResult.error(
              'Could not find Table $selectedTableNumber.');
        }
      }

      order = await service.placeOrder(
        businessId: profile!.businessId!,
        items: items,
        tableId: tableUuid,
        notes: null,
      );

      if (hasKitchen && _isOnline) {
        try {
          final client = _ref.read(supabaseClientProvider);
          await client.from('kitchen_tickets').insert({
            'order_id': order.id,
            'business_id': profile.businessId,
            'status': 'queued',
          });
        } catch (e) {
          debugPrint('[Checkout] Kitchen ticket failed (non-fatal): $e');
        }
      }

      if (isRestaurant && selectedTableNumber != null) {
        _ref.read(tableProvider.notifier).occupyTable(selectedTableNumber, order.id);
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

    if (!hasKitchen) {
      await service.updateStatus(order.id, OrderStatus.completed);
    }

    // ── Receipt — skip business lookup if offline ─────────────────────
    String businessName = 'My Business';
    String? businessAddress;
    String? businessPhone;
    String? businessEmail;

    if (_isOnline) {
      try {
        final client = _ref.read(supabaseClientProvider);
        final businessRow = await client
            .from('businesses')
            .select('name, address, phone, email')
            .eq('id', profile!.businessId!)
            .maybeSingle();
        businessName = businessRow?['name'] as String? ?? 'My Business';
        businessAddress = businessRow?['address'] as String?;
        businessPhone = businessRow?['phone'] as String?;
        businessEmail = businessRow?['email'] as String?;
      } catch (e) {
        debugPrint('[Checkout] Business info fetch failed, using defaults: $e');
      }
    }

    await _ref.read(receiptServiceProvider).createReceipt(
          order: order.copyWith(
            paymentMethod: paymentMethod,
            amountTendered: actualTendered,
            changeAmount: actualChange,
          ),
          businessName: businessName,
          businessAddress: businessAddress,
          businessPhone: businessPhone,
          businessEmail: businessEmail,
          taxRate: 0.12,
          issuedBy: profile!.id,
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