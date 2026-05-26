// lib/core/providers/product_provider.dart

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';

// ── Product list ──────────────────────────────────────────────────────────────

final productListProvider = StreamProvider<List<Product>>((ref) async* {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) {
    yield [];
    return;
  }

  final businessId = profile!.businessId!;
  final local = ref.read(localDbServiceProvider);
  final client = ref.watch(supabaseClientProvider);

  // Immediately yield cached data (includes cached variants) so UI is never blank
  final cached = await local.getProducts(businessId);
  if (cached.isNotEmpty) yield cached;

  // If offline, wait for connectivity
  if (!ref.read(isOnlineProvider)) {
    final completer = Completer<void>();
    final sub = ref.listen<bool>(isOnlineProvider, (_, next) {
      if (next && !completer.isCompleted) completer.complete();
    });
    await completer.future;
    sub.close();
  }

  final controller = StreamController<List<Product>>();

  /// Fetches products + their variants from Supabase, caches locally,
  /// and returns the merged list.
  Future<List<Product>> fetchAll() async {
    // 1. Fetch products
    final rows = await client
        .from('products')
        .select('*, categories(name)')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');

    final products = (rows as List)
        .map((m) => Product.fromMap(m as Map<String, dynamic>))
        .toList();

    await local.upsertProducts(products);

    // 2. Fetch all variants for this business in one query
    if (products.isEmpty) return products;

    final productIds = products.map((p) => p.id).toList();

    // Supabase: fetch variants where product_id is in our product list
    final variantRows = await client
        .from('product_variants')
        .select()
        .eq('is_active', true)
        .inFilter('product_id', productIds);

    final allVariants = (variantRows as List)
        .map((m) => ProductVariant.fromMap(m as Map<String, dynamic>))
        .toList();

    // Cache variants locally (bulk upsert)
    if (allVariants.isNotEmpty) {
      await local.upsertAllVariants(allVariants);
    }

    // 3. Group variants by product_id and attach
    final variantMap = <String, List<ProductVariant>>{};
    for (final v in allVariants) {
      variantMap.putIfAbsent(v.productId, () => []);
      variantMap[v.productId]!.add(v);
    }

    return products.map((p) {
      final variants = variantMap[p.id] ?? [];
      return p.copyWith(variants: variants);
    }).toList();
  }

  void reload() async {
    try {
      controller.add(await fetchAll());
    } catch (e) {
      debugPrint('[productListProvider] reload error: $e');
    }
  }

  // ── Initial fetch from Supabase ──────────────────────────────────────────
  yield await fetchAll();

  // ── App lifecycle: re-fetch when app comes back to foreground ────────────
  final lifecycleObserver = _AppLifecycleObserver(onResume: reload);
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  // ── Realtime subscription ────────────────────────────────────────────────
  final productChannel = client
      .channel('pos_products_$businessId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'products',
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
        table: 'categories',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'business_id',
          value: businessId,
        ),
        callback: (_) => reload(),
      )
      // ── Also listen for variant changes ──────────────────────────────────
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'product_variants',
        callback: (_) => reload(),
      )
      .subscribe((status, [error]) {
        debugPrint(
            '[productListProvider] Realtime status: $status error: $error');
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          debugPrint(
              '[productListProvider] Realtime failed, will rely on lifecycle refresh');
        }
      });

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(lifecycleObserver);
    client.removeChannel(productChannel);
    controller.close();
  });

  yield* controller.stream;
});

// ── Lifecycle observer ────────────────────────────────────────────────────────

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _AppLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[productListProvider] App resumed — refreshing products');
      onResume();
    }
  }
}

// ── Category list ─────────────────────────────────────────────────────────────

final categoryListProvider = FutureProvider<List<String>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) return [];

  final client = ref.watch(supabaseClientProvider);
  final businessId = profile!.businessId!;

  try {
    final rows = await client
        .from('categories')
        .select('name')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('sort_order');
    return (rows as List).map((r) => r['name'] as String).toList();
  } catch (e) {
    final products = ref.read(productListProvider).asData?.value ?? [];
    return products
        .map((p) => p.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
  }
});

bool _fuzzyMatch(String source, String query) {
  if (source.contains(query)) return true;
  int si = 0;
  for (int qi = 0; qi < query.length && si < source.length; qi++) {
    while (si < source.length && source[si] != query[qi]) si++;
    if (si >= source.length) return false;
    si++;
  }
  return true;
}

// ── Selected category ─────────────────────────────────────────────────────────

final selectedCategoryProvider = StateProvider<String?>((ref) => null);
final posSearchQueryProvider = StateProvider<String>((ref) => '');

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productListProvider).asData?.value ?? [];
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(posSearchQueryProvider).toLowerCase().trim();

  bool isVisible(Product p) {
    if (!p.isAvailable) return false;
    // For products with variants, show if any active variant has stock
    // (or if inventory tracking is off)
    if (p.hasVariants) {
      if (!p.trackInventory) return true;
      return p.activeVariants.any((v) => v.stockQuantity > 0);
    }
    if (p.trackInventory && p.stockQuantity <= 0) return false;
    return true;
  }

  return products.where((p) {
    if (!isVisible(p)) return false;
    if (category != null && p.category != category) return false;
    if (query.isNotEmpty) {
      return _fuzzyMatch(p.name.toLowerCase(), query) ||
          p.category.toLowerCase().contains(query) ||
          (p.barcode?.toLowerCase().contains(query) ?? false) ||
          (p.sku?.toLowerCase().contains(query) ?? false);
    }
    return true;
  }).toList();
});

// ── Inventory service ─────────────────────────────────────────────────────────

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(
    client: ref.watch(supabaseClientProvider),
    local: ref.read(localDbServiceProvider),
    syncQueue: ref.read(syncQueueServiceProvider),
    ref: ref,
  );
});

class InventoryService {
  final SupabaseClient _client;
  final LocalDbService _local;
  final SyncQueueService _syncQueue;
  final Ref _ref;

  InventoryService({
    required SupabaseClient client,
    required LocalDbService local,
    required SyncQueueService syncQueue,
    required Ref ref,
  })  : _client = client,
        _local = local,
        _syncQueue = syncQueue,
        _ref = ref;

  Future<void> adjustStock({
    required String businessId,
    required String productId,
    required int quantityChange,
    required int quantityBefore,
    required String action,
    String? notes,
  }) async {
    final quantityAfter = quantityBefore + quantityChange;
    await _local.updateProductStock(productId, quantityAfter);

    final isOnline = _ref.read(isOnlineProvider);

    if (isOnline) {
      try {
        await _client.from('products').update({
          'stock_quantity': quantityAfter,
          'is_available': quantityAfter > 0,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', productId);

        await _client.from('inventory_logs').insert({
          'business_id': businessId,
          'product_id': productId,
          'action': action,
          'quantity_change': quantityChange,
          'quantity_before': quantityBefore,
          'quantity_after': quantityAfter,
          'performed_by': _client.auth.currentUser?.id,
          'notes': notes,
        });
      } catch (e) {
        debugPrint('[InventoryService] Online adjust failed, queuing: $e');
        await _queueAdjust(
          businessId: businessId,
          productId: productId,
          quantityChange: quantityChange,
          action: action,
          notes: notes,
        );
      }
    } else {
      await _queueAdjust(
        businessId: businessId,
        productId: productId,
        quantityChange: quantityChange,
        action: action,
        notes: notes,
      );
    }
  }

  // ── Variant-level stock adjust ────────────────────────────────────────────

  Future<void> adjustVariantStock({
    required String businessId,
    required String variantId,
    required String productId,
    required int quantityChange,
    required int quantityBefore,
    String action = 'sale',
    String? notes,
  }) async {
    final quantityAfter =
        (quantityBefore + quantityChange).clamp(0, 9999);
    await _local.updateVariantStock(variantId, quantityAfter);

    final isOnline = _ref.read(isOnlineProvider);

    if (isOnline) {
      try {
        await _client.from('product_variants').update({
          'stock_quantity': quantityAfter,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', variantId);

        // Still log to inventory_logs at product level for reporting
        await _client.from('inventory_logs').insert({
          'business_id': businessId,
          'product_id': productId,
          'action': action,
          'quantity_change': quantityChange,
          'quantity_before': quantityBefore,
          'quantity_after': quantityAfter,
          'performed_by': _client.auth.currentUser?.id,
          'notes': notes ?? 'Variant: $variantId',
        });
      } catch (e) {
        debugPrint(
            '[InventoryService] Variant adjust failed, queuing: $e');
        await _queueAdjust(
          businessId: businessId,
          productId: variantId, // record_id = variantId so sync knows
          quantityChange: quantityChange,
          action: action,
          notes: notes,
          isVariant: true,
        );
      }
    } else {
      await _queueAdjust(
        businessId: businessId,
        productId: variantId,
        quantityChange: quantityChange,
        action: action,
        notes: notes,
        isVariant: true,
      );
    }
  }

  Future<void> _queueAdjust({
    required String businessId,
    required String productId,
    required int quantityChange,
    required String action,
    String? notes,
    bool isVariant = false,
  }) async {
    await _syncQueue.enqueue(
      operation: isVariant ? 'adjust_variant_stock' : 'adjust_stock',
      tableName: isVariant ? 'product_variants' : 'products',
      recordId: productId,
      payload: {
        'business_id': businessId,
        'quantity_change': quantityChange,
        'action': action,
        'performed_by': _client.auth.currentUser?.id,
        'notes': notes,
      },
    );
  }
}