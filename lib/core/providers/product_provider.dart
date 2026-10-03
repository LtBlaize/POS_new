// lib/core/providers/product_provider.dart
import 'package:uuid/uuid.dart';
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
import '../providers/app_context_provider.dart';

// ── Product list ──────────────────────────────────────────────────────────────

final productListProvider = StreamProvider<List<Product>>((ref) async* {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) {
    yield [];
    return;
  }

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

    // 3. Cache variants locally, then re-read everything from local —
    // this is what attaches local_image_path (Supabase rows never carry
    // it) so the POS grid shows the cached photo immediately instead of
    // falling back to a network image or blank state.
    return local.getProducts(businessId);
  }

  void reload() async {
    if (!ref.read(isOnlineProvider) || controller.isClosed) return;
    try {
      controller.add(await fetchAll());
    } catch (e) {
      debugPrint('[productListProvider] reload error: $e');
    }
  }

  // ── Initial fetch from Supabase ──────────────────────────────────────────
  try {
    yield await fetchAll();
  } catch (e) {
    debugPrint('[productListProvider] initial fetch failed, using cache: $e');
    yield await local.getProducts(businessId);
  }

  // Refresh once whenever connectivity returns.
  ref.listen<bool>(isOnlineProvider, (prev, next) {
    if (next && prev == false) reload();
  });

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
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return [];

  final client = ref.watch(supabaseClientProvider);

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
    while (si < source.length && source[si] != query[qi]) {
      si++;
    }
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
    // A product with variants is always shown as long as the product
    // itself is available. Per-variant stock only disables that specific
    // variant chip inside the picker (see VariantPickerDialog) — it must
    // never hide the whole product from the POS grid. Business rule:
    // adding a variant must never make the parent product disappear.
    if (p.hasVariants) return true;
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
    final after = (quantityBefore + quantityChange).clamp(0, 9999);
    await _local.updateProductStock(productId, after);
    await _apply(
      businessId: businessId,
      productId: productId,
      delta: after - quantityBefore,
      action: action,
      notes: notes,
    );
  }

  Future<void> adjustVariantStock({
    required String businessId,
    required String variantId,
    required String productId,
    required int quantityChange,
    required int quantityBefore,
    String action = 'sale',
    String? notes,
  }) async {
    final after = (quantityBefore + quantityChange).clamp(0, 9999);
    await _local.updateVariantStock(variantId, after);
    await _apply(
      businessId: businessId,
      productId: productId,
      variantId: variantId,
      delta: after - quantityBefore,
      action: action,
      notes: notes,
    );
  }

  /// One idempotency key per adjustment. Online: apply_stock_change() checks
  /// the key, updates stock and writes the log in one transaction. If that
  /// fails (or we're offline) the SAME key is queued, so a retry after a
  /// half-finished attempt is skipped instead of applied twice.
  Future<void> _apply({
    required String businessId,
    required String productId,
    String? variantId,
    required int delta,
    required String action,
    String? notes,
  }) async {
    if (delta == 0) return;
    final key = const Uuid().v4();
    final performedBy = _client.auth.currentUser?.id;

    if (_ref.read(isOnlineProvider)) {
      try {
        await _client.rpc('apply_stock_change', params: {
          'p_business_id': businessId,
          'p_product_id': productId,
          'p_variant_id': variantId,
          'p_delta': delta,
          'p_action': action,
          'p_performed_by': performedBy,
          'p_notes': notes,
          'p_idempotency_key': key,
        });
        return;
      } catch (e) {
        debugPrint('[InventoryService] RPC failed, queuing with same key: $e');
      }
    }

    await _syncQueue.enqueue(
      operation: variantId == null ? 'adjust_stock' : 'adjust_variant_stock',
      tableName: variantId == null ? 'products' : 'product_variants',
      recordId: variantId ?? productId,
      idempotencyKey: key,
      payload: {
        'business_id': businessId,
        'product_id': productId,
        if (variantId != null) 'variant_id': variantId,
        'quantity_change': delta,
        'action': action,
        'performed_by': performedBy,
        'notes': notes,
      },
    );
  }
}