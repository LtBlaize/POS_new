// lib/core/providers/recipe_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../models/promo.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../../features/auth/auth_provider.dart';
import '../../shared/widgets/app_colors.dart';
import 'app_context_provider.dart';
import 'cart_provider.dart';
import 'product_provider.dart';
import '../models/cart_item.dart';

class RecipeLine {
  final String id;
  final String parentProductId;
  final String componentProductId;
  final String? componentVariantId;
  final int quantity;
  final String componentName;
  final String? variantName;
  final bool trackInventory;
  final bool sendToKitchen;
  final double costPrice;

  const RecipeLine({
    required this.id,
    required this.parentProductId,
    required this.componentProductId,
    this.componentVariantId,
    required this.quantity,
    required this.componentName,
    this.variantName,
    required this.trackInventory,
    required this.sendToKitchen,
    required this.costPrice,
  });

  factory RecipeLine.fromRow(Map<String, dynamic> r) {
    final p = r['products'] as Map<String, dynamic>? ?? {};
    final v = r['product_variants'] as Map<String, dynamic>?;
    final vCost = (v?['cost_price'] as num?)?.toDouble() ?? 0;
    final pCost = (p['cost_price'] as num?)?.toDouble() ?? 0;
    return RecipeLine(
      id: r['id'] as String,
      parentProductId: r['parent_product_id'] as String,
      componentProductId: r['component_product_id'] as String,
      componentVariantId: r['component_variant_id'] as String?,
      quantity: r['quantity'] as int,
      componentName: p['name'] as String? ?? 'Unknown product',
      variantName: v?['name'] as String?,
      trackInventory: p['track_inventory'] as bool? ?? false,
      sendToKitchen: p['send_to_kitchen'] as bool? ?? true,
      costPrice: vCost > 0 ? vCost : pCost,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'parent_product_id': parentProductId,
    'component_product_id': componentProductId,
    'component_variant_id': componentVariantId,
    'quantity': quantity,
    'name': componentName,
    'variant_name': variantName,
    'track_inventory': trackInventory,
    'send_to_kitchen': sendToKitchen,
    'cost_price': costPrice,
  };

  factory RecipeLine.fromJson(Map<String, dynamic> j) => RecipeLine(
    id: j['id'] as String,
    parentProductId: j['parent_product_id'] as String,
    componentProductId: j['component_product_id'] as String,
    componentVariantId: j['component_variant_id'] as String?,
    quantity: j['quantity'] as int,
    componentName: j['name'] as String,
    variantName: j['variant_name'] as String?,
    trackInventory: j['track_inventory'] as bool? ?? false,
    sendToKitchen: j['send_to_kitchen'] as bool? ?? true,
    costPrice: (j['cost_price'] as num?)?.toDouble() ?? 0,
  );
}

Map<String, List<RecipeLine>> _group(List<RecipeLine> lines) {
  final m = <String, List<RecipeLine>>{};
  for (final l in lines) {
    m.putIfAbsent(l.parentProductId, () => []).add(l);
  }
  return m;
}

/// parent product id -> its recipe lines. Online: fetched and cached in
/// kv_cache. Offline: read from that cache.
final recipesProvider = FutureProvider<Map<String, List<RecipeLine>>>((
  ref,
) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return {};
  final online = ref.watch(isOnlineProvider);
  final local = ref.read(localDbServiceProvider);
  final key = 'recipes_$businessId';

  if (online) {
    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('product_components')
          .select(
            '*, products!component_product_id(name, track_inventory, send_to_kitchen, cost_price), product_variants(name, cost_price)',
          )
          .eq('business_id', businessId);
      final lines =
          (rows as List)
              .map((r) => RecipeLine.fromRow(r as Map<String, dynamic>))
              .toList();
      await local.setKv(key, lines.map((l) => l.toJson()).toList());
      return _group(lines);
    } catch (e) {
      debugPrint('[Recipes] fetch failed, using cache: $e');
    }
  }
  final cached = await local.getKv(key);
  if (cached is! List) return {};
  return _group(
    cached
        .map((j) => RecipeLine.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList(),
  );
});

/// Replaces any component that is itself a recipe product with its parts
/// (nested up to 3 levels). Components without a recipe pass through.
List<PromoComponent> expandComponents(
  List<PromoComponent> input,
  Map<String, List<RecipeLine>> recipes, {
  int depth = 0,
}) {
  final out = <PromoComponent>[];
  for (final c in input) {
    final lines = c.variantId == null ? recipes[c.productId] : null;
    if (lines == null || lines.isEmpty || depth >= 3) {
      out.add(c);
      continue;
    }
    final sub = [
      for (final l in lines)
        PromoComponent(
          promoId: c.promoId,
          productId: l.componentProductId,
          variantId: l.componentVariantId,
          productName: l.componentName,
          variantName: l.variantName,
          quantity: l.quantity * c.quantity,
          trackInventory: l.trackInventory,
          sendToKitchen: l.sendToKitchen,
        ),
    ];
    out.addAll(expandComponents(sub, recipes, depth: depth + 1));
  }
  if (depth > 0) return out;
  final merged = <String, PromoComponent>{};
  for (final c in out) {
    final k = '${c.productId}|${c.variantId ?? ''}';
    final e = merged[k];
    merged[k] =
        e == null
            ? c
            : PromoComponent(
              promoId: e.promoId,
              productId: e.productId,
              variantId: e.variantId,
              productName: e.productName,
              variantName: e.variantName,
              quantity: e.quantity + c.quantity,
              trackInventory: e.trackInventory,
              sendToKitchen: e.sendToKitchen,
            );
  }
  return merged.values.toList();
}

/// Returns an error message for the first component with too little stock.
String? componentStockError(
  List<Product> live,
  List<PromoComponent> components,
) {
  for (final c in components) {
    if (!c.trackInventory) continue;
    final p = live.where((p) => p.id == c.productId).firstOrNull;
    if (p == null) continue;
    final available =
        c.variantId != null
            ? p.variants
                .where((v) => v.id == c.variantId)
                .firstOrNull
                ?.stockQuantity
            : p.stockQuantity;
    if (available != null && c.quantity > available) {
      final label =
          c.variantName != null
              ? '${c.productName} (${c.variantName})'
              : c.productName;
      return '$label only has $available in stock (this needs ${c.quantity}).';
    }
  }
  return null;
}

/// Call this from the POS product tap. Returns true if [p] has a recipe and
/// was handled (added to cart or refused); false means add it normally.
bool handleRecipeTap(BuildContext context, WidgetRef ref, Product p) {
  final recipes = ref.read(recipesProvider).asData?.value ?? const {};
  final lines = recipes[p.id];
  if (lines == null || lines.isEmpty) return false;

  final components = expandComponents([
    PromoComponent(
      promoId: '',
      productId: p.id,
      productName: p.name,
      quantity: 1,
      trackInventory: false,
      sendToKitchen: p.sendToKitchen,
    ),
  ], recipes);

  final live = ref.read(productListProvider).asData?.value ?? [];
  final error = cartAwareStockError(live, ref.read(cartProvider), components);
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 2),
      ),
    );
    return true;
  }

  var cost = componentsCost(live, components);
  if (cost <= 0) {
    cost = lines.fold<double>(0, (s, l) => s + l.costPrice * l.quantity);
  }
  ref.read(cartProvider.notifier).addRecipeProduct(p, components, cost);
  return true;
}

// ── Save ─────────────────────────────────────────────────────────────────────

class RecipeDraftLine {
  final String productId;
  final String? variantId;
  final int quantity;
  const RecipeDraftLine(this.productId, this.variantId, this.quantity);
}

Future<void> saveRecipe(
  WidgetRef ref, {
  required String parentProductId,
  required List<RecipeDraftLine> lines,
}) async {
  final businessId = ref.read(activeBusinessIdProvider);
  if (businessId == null) throw Exception('No business profile found.');
  final client = ref.read(supabaseClientProvider);
  await client
      .from('product_components')
      .delete()
      .eq('parent_product_id', parentProductId);
  if (lines.isNotEmpty) {
    await client.from('product_components').insert([
      for (final l in lines)
        {
          'business_id': businessId,
          'parent_product_id': parentProductId,
          'component_product_id': l.productId,
          'component_variant_id': l.variantId,
          'quantity': l.quantity,
        },
    ]);
  }
  ref.invalidate(recipesProvider);
}

/// Like componentStockError, but counts what the cart already holds
/// (plain lines, promo and recipe components) before adding [adding].
String? cartAwareStockError(
  List<Product> live,
  List<CartItem> cart,
  List<PromoComponent> adding,
) {
  String key(String pid, String? vid) => '$pid|${vid ?? ''}';
  final demand = <String, int>{};
  for (final i in cart) {
    if (i.isPromo) {
      for (final c in i.promoComponents!) {
        if (!c.trackInventory) continue;
        final k = key(c.productId, c.variantId);
        demand[k] = (demand[k] ?? 0) + c.quantity * i.quantity;
      }
    } else if (i.product.trackInventory && !i.product.isCustom) {
      final k = key(i.product.id, i.selectedVariant?.id);
      demand[k] = (demand[k] ?? 0) + i.quantity;
    }
  }
  final adds = <String, int>{};
  for (final c in adding) {
    if (!c.trackInventory) continue;
    final k = key(c.productId, c.variantId);
    adds[k] = (adds[k] ?? 0) + c.quantity;
  }
  for (final c in adding) {
    if (!c.trackInventory) continue;
    final k = key(c.productId, c.variantId);
    final add = adds.remove(k);
    if (add == null) continue; // already checked
    final p = live.where((p) => p.id == c.productId).firstOrNull;
    if (p == null) continue;
    final available =
        c.variantId != null
            ? p.variants
                .where((v) => v.id == c.variantId)
                .firstOrNull
                ?.stockQuantity
            : p.stockQuantity;
    final total = (demand[k] ?? 0) + add;
    if (available != null && total > available) {
      final label =
          c.variantName != null
              ? '${c.productName} (${c.variantName})'
              : c.productName;
      return '$label only has $available in stock ($total would be in the cart).';
    }
  }
  return null;
}

/// Per-unit cost of [components], from live product/variant costs.
double componentsCost(List<Product> live, List<PromoComponent> components) {
  var t = 0.0;
  for (final c in components) {
    final p = live.where((p) => p.id == c.productId).firstOrNull;
    if (p == null) continue;
    final v =
        c.variantId == null
            ? null
            : p.variants.where((v) => v.id == c.variantId).firstOrNull;
    t +=
        ((v != null && v.costPrice > 0) ? v.costPrice : p.costPrice) *
        c.quantity;
  }
  return t;
}
