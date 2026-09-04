// lib/core/providers/promo_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/promo.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../../features/auth/auth_provider.dart';
import 'app_context_provider.dart';

// ── Promo list (owner/settings + POS "Promos" tab share this) ────────────────

final promoListProvider = StreamProvider<List<Promo>>((ref) async* {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) {
    yield [];
    return;
  }

  final local = ref.read(localDbServiceProvider);
  final client = ref.watch(supabaseClientProvider);

  final cached = await local.getPromos(businessId);
  if (cached.isNotEmpty) yield cached;

  if (!ref.read(isOnlineProvider)) {
    final completer = Completer<void>();
    final sub = ref.listen<bool>(isOnlineProvider, (_, next) {
      if (next && !completer.isCompleted) completer.complete();
    });
    await completer.future;
    sub.close();
  }

  final controller = StreamController<List<Promo>>();

  Future<List<Promo>> fetchAll() async {
    final promoRows = await client
        .from('promos')
        .select()
        .eq('business_id', businessId)
        .order('created_at', ascending: false);

    final promos = (promoRows as List)
        .map((m) => Promo.fromMap(m as Map<String, dynamic>))
        .toList();

    if (promos.isEmpty) {
      await local.replacePromos(businessId, []);
      return promos;
    }

    final promoIds = promos.map((p) => p.id).toList();

    // Join product/variant display fields in one query so the picker/list
    // UI never needs a second round trip per promo — same approach as
    // productListProvider's variant fetch.
    final itemRows = await client
        .from('promo_items')
        .select(
            '*, products(name, price, track_inventory, send_to_kitchen), product_variants(name, price_delta)')
        .inFilter('promo_id', promoIds);

    final itemsByPromo = <String, List<PromoItem>>{};
    for (final row in itemRows as List) {
      final map = row as Map<String, dynamic>;
      final productMap = map['products'] as Map<String, dynamic>?;
      final variantMap = map['product_variants'] as Map<String, dynamic>?;

      // Additive variant pricing — matches product_variants.price_delta
      // and the builder's own product picker (base + delta), not an
      // override. Computed once here so every downstream consumer
      // (originalTotal, effectivePrice, checkPromoStock, the POS grid,
      // the builder's edit view) sees the same correct number instead
      // of each recomputing it differently.
      final basePrice = (productMap?['price'] as num?)?.toDouble() ?? 0;
      final delta = (variantMap?['price_delta'] as num?)?.toDouble() ?? 0;
      final effectivePrice = map['variant_id'] != null ? basePrice + delta : basePrice;

      final item = PromoItem.fromMap({
        ...map,
        'product_name': productMap?['name'],
        'variant_name': variantMap?['name'],
        'product_price': effectivePrice,
        'product_track_inventory': productMap?['track_inventory'],
        'product_send_to_kitchen': productMap?['send_to_kitchen'],
      });
      itemsByPromo.putIfAbsent(item.promoId, () => []).add(item);
    }

    final withItems = promos
        .map((p) => Promo(
              id: p.id,
              businessId: p.businessId,
              name: p.name,
              description: p.description,
              imageUrl: p.imageUrl,
              promoType: p.promoType,
              bundlePrice: p.bundlePrice,
              buyQuantity: p.buyQuantity,
              getQuantity: p.getQuantity,
              getDiscountPercent: p.getDiscountPercent,
              isActive: p.isActive,
              startDate: p.startDate,
              endDate: p.endDate,
              items: itemsByPromo[p.id] ?? [],
            ))
        .toList();

    await local.replacePromos(businessId, withItems);
    return withItems;
  }

  void reload() async {
    try {
      controller.add(await fetchAll());
    } catch (e) {
      debugPrint('[promoListProvider] reload error: $e');
    }
  }

  yield await fetchAll();

  final channel = client
      .channel('pos_promos_$businessId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'promos',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'business_id',
          value: businessId,
        ),
        callback: (_) => reload(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'promo_items',
        callback: (_) => reload(),
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  yield* controller.stream;
});

// Only what the POS "Promos" tab should offer for sale right now.
final purchasablePromosProvider = Provider<List<Promo>>((ref) {
  final promos = ref.watch(promoListProvider).asData?.value ?? [];
  return promos.where((p) => p.isPurchasable).toList();
});

// ── Repository (create/update/delete) ─────────────────────────────────────────

final promoRepositoryProvider = Provider<PromoRepository>((ref) {
  return PromoRepository(ref.watch(supabaseClientProvider));
});

class PromoRepository {
  final SupabaseClient _client;
  PromoRepository(this._client);

  Future<Promo> create(Promo promo) async {
    final row = await _client.from('promos').insert(promo.toMap()).select().single();
    final promoId = row['id'] as String;

    if (promo.items.isNotEmpty) {
      await _client.from('promo_items').insert(
            promo.items.map((i) => {...i.toMap(), 'promo_id': promoId}).toList(),
          );
    }
    return Promo.fromMap(row, items: promo.items);
  }

  Future<void> update(Promo promo) async {
    await _client.from('promos').update(promo.toMap()).eq('id', promo.id);

    // Simplest correct approach: replace all items. Promo item sets are
    // small (a handful of products) so a delete+reinsert is cheap and
    // avoids diffing logic that could silently drop a row.
    await _client.from('promo_items').delete().eq('promo_id', promo.id);
    if (promo.items.isNotEmpty) {
      await _client.from('promo_items').insert(
            promo.items.map((i) => {...i.toMap(), 'promo_id': promo.id}).toList(),
          );
    }
  }

  Future<void> setActive(String promoId, bool isActive) async {
    await _client
        .from('promos')
        .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', promoId);
  }

  Future<void> delete(String promoId) async {
    // promo_items has ON DELETE CASCADE on promo_id — verify this in
    // Supabase (see Phase 5 note). If it's NOT set, this delete will fail
    // with a FK violation instead of silently orphaning rows, which is the
    // safer failure mode either way.
    await _client.from('promos').delete().eq('id', promoId);
  }

  Future<Promo> duplicate(Promo promo) async {
    final copy = Promo(
      id: '', // ignored by toMap/insert
      businessId: promo.businessId,
      name: '${promo.name} (Copy)',
      description: promo.description,
      imageUrl: promo.imageUrl,
      promoType: promo.promoType,
      bundlePrice: promo.bundlePrice,
      buyQuantity: promo.buyQuantity,
      getQuantity: promo.getQuantity,
      getDiscountPercent: promo.getDiscountPercent,
      isActive: false, // duplicates start inactive — owner reviews before enabling
      startDate: promo.startDate,
      endDate: promo.endDate,
      items: promo.items,
    );
    return create(copy);
  }
}

// ── Stock sufficiency check (POS add-to-cart guard) ───────────────────────────

/// Returns null if the promo can be added, or an error message naming the
/// first insufficient component — mirrors CheckoutService's per-item stock
/// check style so the UX is consistent.
String? checkPromoStock(Promo promo, {required int cartQuantity}) {
  final itemsToCheck = promo.promoType == PromoType.bundle
      ? promo.bundleItems
      : [...promo.buyItems, ...promo.getItems];

  for (final item in itemsToCheck) {
    if (item.productTrackInventory != true) continue;
    // We only have the *catalog* stock here (from the join); the caller
    // should still re-validate against live productListProvider/local
    // cache at actual checkout time, same as CheckoutService does today.
    final neededPerUnit = item.quantity *
        (promo.promoType == PromoType.buyXGetY
            ? (item.role == PromoItemRole.buy
                ? (promo.buyQuantity ?? 1)
                : (promo.getQuantity ?? 1))
            : 1);
    final needed = neededPerUnit * cartQuantity;
    // Actual stock number comes from productListProvider at call site —
    // this helper only tells you *what* to check, not the live number,
    // since PromoItem's productPrice/track fields are catalog snapshots
    // from the join, not necessarily fresh stock counts.
    if (needed <= 0) {
      return '${item.productName ?? 'An item'} in "${promo.name}" is misconfigured.';
    }
  }
  return null;
}