// lib/core/providers/cart_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/promo.dart';


// REPLACE
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]) {
    _restoreDraft();
  }

  static const _draftKey = 'draft_cart_v1';
  Timer? _persistDebounce;
  bool _restoringDraft = true;

  double orderDiscountAmount = 0;
  DiscountType orderDiscountType = DiscountType.fixed;
  OrderType orderType = OrderType.walkIn;

  /// Silently reloads whatever cart was in progress when the app last
  /// closed/crashed, so a restart drops the user back where they were.
  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null) return;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      final items = (map['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(CartItem.fromParkedMap)
          .toList();
      if (items.isEmpty) return;

      orderDiscountAmount =
          (map['order_discount_amount'] as num?)?.toDouble() ?? 0;
      orderDiscountType = DiscountType.values.firstWhere(
        (e) => e.name == map['order_discount_type'],
        orElse: () => DiscountType.fixed,
      );
      orderType = OrderType.values.firstWhere(
        (e) => e.name == map['order_type'],
        orElse: () => OrderType.walkIn,
      );
      _tipAmount = (map['tip_amount'] as num?)?.toDouble() ?? 0;
      state = items;
      debugPrint('[Cart] Restored draft cart (${items.length} item(s))');
    } catch (e) {
      debugPrint('[Cart] Draft restore failed: $e');
    } finally {
      _restoringDraft = false;
    }
  }

  /// Debounced write-through so a burst of taps (e.g. tapping +3 quickly)
  /// doesn't hit disk on every single tap.
  void _persist() {
    if (_restoringDraft) return; // don't immediately re-save what we just loaded
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (state.isEmpty) {
          await prefs.remove(_draftKey);
          return;
        }
        final map = {
          'items': state.map((i) => i.toParkedMap()).toList(),
          'order_discount_amount': orderDiscountAmount,
          'order_discount_type': orderDiscountType.name,
          'order_type': orderType.name,
          'tip_amount': _tipAmount,
        };
        await prefs.setString(_draftKey, jsonEncode(map));
      } catch (e) {
        debugPrint('[Cart] Draft persist failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    super.dispose();
  }

  void setOrderType(OrderType type) {
    orderType = type;
    state = [...state];
    _persist();
  }

  void applyOrderDiscount(double amount, DiscountType type) {
    orderDiscountAmount = amount;
    orderDiscountType = type;
    state = [...state]; // trigger rebuild
    _persist();
  }

  void applyItemDiscount(String productId, double amount, DiscountType type) {
    final index = state.indexWhere((i) => i.product.id == productId);
    if (index < 0) return;
    final updated = List<CartItem>.from(state);
    final item = state[index];
    updated[index] = CartItem(
      product: item.product,
      selectedVariant: item.selectedVariant,
      quantity: item.quantity,
      discountAmount: amount,
      discountType: type,
      costAtSale: item.costAtSale,
      notes: item.notes,
      promoComponents: item.promoComponents,
      promoId: item.promoId,
    );
    state = updated;
  }

  void setItemNotes(String productId, String? notes) {
    final index = state.indexWhere((i) => i.product.id == productId);
    if (index < 0) return;
    final updated = List<CartItem>.from(state);
    final item = state[index];
    updated[index] = CartItem(
      product: item.product,
      selectedVariant: item.selectedVariant,
      quantity: item.quantity,
      discountAmount: item.discountAmount,
      discountType: item.discountType,
      costAtSale: item.costAtSale,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      promoComponents: item.promoComponents,
      promoId: item.promoId,
    );
    state = updated;
  }

  double get itemsTotal => state.fold(0, (sum, item) => sum + item.total);

  double get orderDiscountValue {
    if (orderDiscountType == DiscountType.percentage) {
      return itemsTotal * (orderDiscountAmount / 100);
    }
    return orderDiscountAmount;
  }

 double _tipAmount = 0;
  double get tipAmount => _tipAmount;

  void setTip(double amount) {
    _tipAmount = amount.clamp(0, double.infinity);
    state = [...state]; // trigger rebuild
    _persist();
  }

  double get grandTotal => (itemsTotal - orderDiscountValue + _tipAmount).clamp(0, double.infinity);

  void addProduct(Product product, {ProductVariant? variant}) {
    final index = state.indexWhere((item) =>
        item.product.id == product.id &&
        item.selectedVariant?.id == variant?.id);
    if (index >= 0) {
      final current = state[index];
      final stockCap = variant != null
          ? variant.stockQuantity
          : product.stockQuantity;
      if (product.trackInventory && current.quantity >= stockCap) {
        return;
      }

      final updated = List<CartItem>.from(state);
      updated[index] = CartItem(
        product: current.product,
        selectedVariant: current.selectedVariant,
        quantity: current.quantity + 1,
        discountAmount: current.discountAmount,
        discountType: current.discountType,
        costAtSale: current.costAtSale,
        notes: current.notes,
        promoComponents: current.promoComponents,
        promoId: current.promoId,
      );
      state = updated;
    } else {
      state = [...state, CartItem(product: product, selectedVariant: variant)];
    }
    _persist();
  }

  void decrementProduct(String productId) {
    final index = state.indexWhere((item) => item.product.id == productId);
    if (index < 0) return;
    final current = state[index];
    if (current.quantity <= 1) {
      removeProduct(productId);
    } else {
      final updated = List<CartItem>.from(state);
      updated[index] = CartItem(
        product: current.product,
        selectedVariant: current.selectedVariant,
        quantity: current.quantity - 1,
        discountAmount: current.discountAmount,
        discountType: current.discountType,
        costAtSale: current.costAtSale,
        notes: current.notes,
        promoComponents: current.promoComponents,
        promoId: current.promoId,
      );
      state = updated;
    }
    _persist();
  }

  void removeProduct(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
    _persist();
  }

  /// Adds one unit of [promo] to the cart, expanded into [components] for
  /// inventory/kitchen/receipt purposes. Live stock sufficiency must already
  /// have been checked by the caller (POS widget) — this method does not
  /// re-validate stock, matching how addProduct's own stockCap check only
  /// covers the simple single-product case.
  void addPromo(Promo promo, List<PromoComponent> components) {
    final promoProduct = Product.promo(
      id: 'promo_${promo.id}',
      name: promo.name,
      price: promo.effectivePrice,
      imageUrl: promo.imageUrl,
    );
    final index = state.indexWhere((item) => item.product.id == promoProduct.id);
    if (index >= 0) {
      final current = state[index];
      final updated = List<CartItem>.from(state);
      updated[index] = CartItem(
        product: current.product,
        quantity: current.quantity + 1,
        discountAmount: current.discountAmount,
        discountType: current.discountType,
        costAtSale: current.costAtSale,
        notes: current.notes,
        promoComponents: current.promoComponents,
        promoId: current.promoId,
      );
      state = updated;
    } else {
      state = [
        ...state,
        CartItem(
          product: promoProduct,
          quantity: 1,
          costAtSale: 0, // promo COGS not tracked from components yet — see note in final report
          promoComponents: components,
          promoId: promo.id,
        ),
      ];
    }
    _persist();
  }

  void clear() {
    orderDiscountAmount = 0;
    orderDiscountType = DiscountType.fixed;
    _tipAmount = 0;
    orderType = OrderType.walkIn;
    state = [];
    _persistDebounce?.cancel();
    SharedPreferences.getInstance().then((p) => p.remove(_draftKey));
  }

  void loadItems(
    List<CartItem> items, {
    double orderDiscountAmount = 0,
    DiscountType orderDiscountType = DiscountType.fixed,
    double tipAmount = 0,
  }) {
    this.orderDiscountAmount = orderDiscountAmount;
    this.orderDiscountType = orderDiscountType;
    _tipAmount = tipAmount;
    state = List.from(items);
    _persist();
  }

  double get total => grandTotal;
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);