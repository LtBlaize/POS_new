import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/product.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/providers/product_provider.dart';
import '../../config/business_config.dart';
import '../../core/providers/app_context_provider.dart';
import '../../core/models/product_variant.dart';

// ── InventoryEntry ────────────────────────────────────────────────────────────

class InventoryEntry {
  final Product product;
  final int lowStockThreshold;

  const InventoryEntry({
    required this.product,
    this.lowStockThreshold = 5,
  });

  int get stock => product.effectiveStock;

  bool get isLowStock {
    if (!product.trackInventory) return false;
    if (product.hasVariants) {
      return product.activeVariants
          .any((v) => v.stockQuantity <= lowStockThreshold);
    }
    return stock <= lowStockThreshold;
  }

  InventoryEntry copyWith({Product? product, int? lowStockThreshold}) {
    return InventoryEntry(
      product: product ?? this.product,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    );
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class InventoryState {
  final List<InventoryEntry> entries;
  final bool loading;
  final String? error;
  final bool isOffline;
  final String? lowStockAlert; // non-null = show alert banner

  const InventoryState({
    this.entries = const [],
    this.loading = false,
    this.error,
    this.isOffline = false,
    this.lowStockAlert,
  });

  InventoryState copyWith({
    List<InventoryEntry>? entries,
    bool? loading,
    String? error,
    bool? isOffline,
    String? lowStockAlert,
  }) =>
      InventoryState(
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        error: error,
        isOffline: isOffline ?? this.isOffline,
        lowStockAlert: lowStockAlert,
      );

  List<InventoryEntry> get lowStockItems =>
      entries.where((e) => e.isLowStock).toList();

  List<InventoryEntry> get trackedItems =>
      entries.where((e) => e.product.trackInventory).toList();
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class InventoryNotifier extends StateNotifier<InventoryState> {
  final SupabaseClient _client;
  final String _businessId;
  final LocalDbService _local;
  final SyncQueueService _syncQueue;
  final Ref _ref;
  RealtimeChannel? _channel;

  InventoryNotifier({
    required SupabaseClient client,
    required String businessId,
    required LocalDbService local,
    required SyncQueueService syncQueue,
    required Ref ref,
  })  : _client = client,
        _businessId = businessId,
        _local = local,
        _syncQueue = syncQueue,
        _ref = ref,
        super(const InventoryState(loading: true)) {
    if (_businessId.isEmpty) {
      state = const InventoryState(loading: false);
      return;
    }
    _load();
    _subscribeRealtime();
  }

  bool get _isOnline => _ref.read(isOnlineProvider);

  // Forces productListProvider to re-fetch.
  void _refreshProductList() {
    try {
      _ref.invalidate(productListProvider);
    } catch (e) {
      debugPrint('[Inventory] Failed to invalidate productListProvider: $e');
    }
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    if (!_isOnline) return;
    try {
      _channel = _client
          .channel('inventory_products_$_businessId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'products',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'business_id',
              value: _businessId,
            ),
            callback: (payload) {
              debugPrint('📦 Realtime inventory change: ${payload.eventType}');
              _load();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'product_variants',
            callback: (_) => _load(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('[Inventory] Realtime subscribe failed (offline?): $e');
    }
  }

  @override
  void dispose() {
    if (_channel != null) {
      try {
        _client.removeChannel(_channel!);
      } catch (_) {}
    }
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (_businessId.isEmpty) return;
    state = state.copyWith(loading: true, error: null);

    try {
      final cached = await _local.getProducts(_businessId);
      if (cached.isNotEmpty) {
        state = state.copyWith(
          entries: cached.map((p) => InventoryEntry(product: p)).toList(),
          loading: true,
          isOffline: !_isOnline,
        );
      }
    } catch (e) {
      debugPrint('[Inventory] Cache read failed: $e');
    }

    if (!_isOnline) {
      state = state.copyWith(loading: false, isOffline: true);
      return;
    }

    try {
      final rows = await _client
          .from('products')
          .select('*, categories(name)')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('name');

      final threshold =
          _ref.read(businessConfigProvider)?.lowStockThreshold ?? 5;

      final products = (rows as List)
          .map((row) => Product.fromMap(row as Map<String, dynamic>))
          .toList();

      await _local.upsertProducts(products);

      if (products.isNotEmpty) {
        final variantRows = await _client
            .from('product_variants')
            .select()
            .eq('is_active', true)
            .inFilter('product_id', products.map((p) => p.id).toList());
        final variants = (variantRows as List)
            .map((m) => ProductVariant.fromMap(m as Map<String, dynamic>))
            .toList();
        if (variants.isNotEmpty) await _local.upsertAllVariants(variants);
      }

      // Re-read from local cache so local_image_path shows up immediately.
      final mergedProducts = await _local.getProducts(_businessId);
      final entries = mergedProducts
          .map((p) => InventoryEntry(product: p, lowStockThreshold: threshold))
          .toList();

      state = state.copyWith(
        entries: entries,
        loading: false,
        isOffline: false,
      );

      await _checkLowStockAlerts(entries, threshold);
    } catch (e, stack) {
      debugPrint('[Inventory] Supabase load failed: $e\n$stack');
      state = state.copyWith(
        loading: false,
        error: _isOnline ? e.toString() : null,
        isOffline: !_isOnline,
      );
    }
  }

  Future<void> refresh() => _load();

  void dismissAlert() => state = state.copyWith(lowStockAlert: null);

  // ── Atomic stock write (shared by product + variant paths) ────────────────
  //
  // One idempotency key per adjustment. Online: call apply_stock_change(),
  // which checks the key, updates stock and writes the log in one transaction.
  // If the call fails (or we're offline) the SAME key is queued, so a retry
  // after a half-finished attempt is skipped by the server instead of being
  // applied twice.

  Future<void> _applyStock({
    required String productId,
    String? variantId,
    required String businessId,
    required int delta,
    required String action,
    String? notes,
  }) async {
    if (delta == 0) return;
    final key = const Uuid().v4();
    final performedBy = _client.auth.currentUser?.id;

    if (_isOnline) {
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
        debugPrint('[Inventory] Stock RPC failed, queuing with same key: $e');
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

  // ── Adjust stock ──────────────────────────────────────────────────────────

  Future<void> adjustStock(
    String productId,
    int delta, {
    String action = 'adjustment',
    String? notes,
  }) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;

    final entry = state.entries[index];
    final before = entry.stock;
    final after = (before + delta).clamp(0, 9999);

    // Optimistic UI + local SQLite first.
    _updateEntry(
        index,
        entry.copyWith(
          product: entry.product.copyWith(stockQuantity: after),
        ));
    await _local.updateProductStock(productId, after);
    _refreshProductList();

    await _applyStock(
      productId: productId,
      businessId: _businessId,
      delta: after - before,
      action: action,
      notes: notes,
    );
    _refreshProductList();
  }

  // ── Set stock ─────────────────────────────────────────────────────────────

  Future<void> setStock(String productId, int value, {String? notes}) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;

    final entry = state.entries[index];
    final before = entry.stock;
    final after = value.clamp(0, 9999);

    _updateEntry(
        index,
        entry.copyWith(
          product: entry.product.copyWith(stockQuantity: after),
        ));
    await _local.updateProductStock(productId, after);
    _refreshProductList();

    await _applyStock(
      productId: productId,
      businessId: _businessId,
      delta: after - before,
      action: 'adjustment',
      notes: notes ?? 'Manual stock set',
    );
    _refreshProductList();
  }

  // ── Toggle availability ───────────────────────────────────────────────────

  Future<void> toggleAvailability(String productId) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;

    final entry = state.entries[index];
    final newVal = !entry.product.isAvailable;

    _updateEntry(
        index,
        entry.copyWith(
          product: entry.product.copyWith(isAvailable: newVal),
        ));

    await _local.updateProductAvailability(productId, newVal);
    _refreshProductList();

    if (_isOnline) {
      try {
        await _client.from('products').update({
          'is_available': newVal,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', productId);
        _refreshProductList();
      } catch (e) {
        _updateEntry(index, entry);
        await _local.updateProductAvailability(
            productId, entry.product.isAvailable);
        _refreshProductList();
        state = state.copyWith(error: 'Failed to update availability: $e');
      }
    }
  }

  Future<void> restock(String productId, int quantity, {String? notes}) =>
      adjustStock(productId, quantity,
          action: 'restock', notes: notes ?? 'Restock');

  // ── Low stock alerts ──────────────────────────────────────────────────────

  Future<void> _checkLowStockAlerts(
    List<InventoryEntry> entries,
    int threshold,
  ) async {
    try {
      final config = _ref.read(businessConfigProvider);
      if (config == null || !config.enableInventoryAlerts) return;

      final lowItems = entries.where((e) => e.isLowStock).toList();
      if (lowItems.isEmpty) return;

      final alreadyAlerted =
          await _local.getRecentlyAlertedProductIds(_businessId);

      final toAlert = lowItems
          .where((e) => !alreadyAlerted.contains(e.product.id))
          .toList();
      if (toAlert.isEmpty) return;

      // Mark first so concurrent loads don't double-fire.
      for (final entry in toAlert) {
        await _local.markLowStockAlerted(
          productId: entry.product.id,
          businessId: _businessId,
          productName: entry.product.name,
          stockQuantity: entry.stock,
        );
      }

      final names = toAlert.take(3).map((e) => e.product.name).join(', ');
      final extra = toAlert.length > 3 ? ' +${toAlert.length - 3} more' : '';
      final message =
          '${toAlert.length} item${toAlert.length > 1 ? 's' : ''} low: $names$extra';

      debugPrint('[Inventory] Low stock alert: $message');
      state = state.copyWith(lowStockAlert: message);
    } catch (e) {
      debugPrint('[Inventory] Alert check failed: $e');
    }
  }

  void _updateEntry(int index, InventoryEntry updated) {
    final list = List<InventoryEntry>.from(state.entries);
    list[index] = updated;
    state = state.copyWith(entries: list);
  }

  // ── Variant stock (used by the inventory list) ────────────────────────────

  Future<void> adjustVariant(
    String productId,
    String variantId,
    int delta, {
    String action = 'adjustment',
    String? notes,
  }) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;
    final entry = state.entries[index];
    final vIdx = entry.product.variants.indexWhere((v) => v.id == variantId);
    if (vIdx < 0) return;

    final before = entry.product.variants[vIdx].stockQuantity;
    final after = (before + delta).clamp(0, 9999);
    if (after == before) return;

    final newVariants = List<ProductVariant>.from(entry.product.variants);
    newVariants[vIdx] = newVariants[vIdx].copyWith(stockQuantity: after);
    _updateEntry(index,
        entry.copyWith(product: entry.product.copyWith(variants: newVariants)));

    await adjustVariantStock(
      businessId: _businessId,
      productId: productId,
      variantId: variantId,
      quantityChange: after - before,
      quantityBefore: before,
      action: action,
      notes: notes,
    );
    _refreshProductList();
  }

  Future<void> restockVariant(String productId, String variantId, int qty,
          {String? notes}) =>
      adjustVariant(productId, variantId, qty,
          action: 'restock', notes: notes ?? 'Restock');

  Future<void> setVariantStock(String productId, String variantId, int value,
      {String? notes}) async {
    final entry = state.entries.firstWhere((e) => e.product.id == productId);
    final current = entry.product.variants
        .firstWhere((v) => v.id == variantId)
        .stockQuantity;
    await adjustVariant(productId, variantId, value.clamp(0, 9999) - current,
        notes: notes ?? 'Manual stock set');
  }

  // ── Variant stock adjustment (low-level) ──────────────────────────────────

  Future<void> adjustVariantStock({
    required String businessId,
    required String productId,
    required String variantId,
    required int quantityChange,
    required int quantityBefore,
    required String action,
    String? notes,
  }) async {
    final after = (quantityBefore + quantityChange).clamp(0, 9999);

    await _local.updateVariantStock(variantId, after);

    // after - quantityBefore (not quantityChange) so a clamp at 0 is logged
    // accurately.
    await _applyStock(
      productId: productId,
      variantId: variantId,
      businessId: businessId,
      delta: after - quantityBefore,
      action: action,
      notes: notes,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final inventoryProvider =
    StateNotifierProvider<InventoryNotifier, InventoryState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final businessId = ref.watch(activeBusinessIdProvider) ?? '';
  final local = ref.read(localDbServiceProvider);
  final syncQueue = ref.read(syncQueueServiceProvider);

  return InventoryNotifier(
    client: client,
    businessId: businessId,
    local: local,
    syncQueue: syncQueue,
    ref: ref,
  );
});

final lowStockProvider = Provider<List<InventoryEntry>>((ref) {
  return ref.watch(inventoryProvider).lowStockItems;
});

final trackedInventoryProvider = Provider<List<InventoryEntry>>((ref) {
  return ref.watch(inventoryProvider).trackedItems;
});