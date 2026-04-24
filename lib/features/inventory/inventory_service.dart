import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/product.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';

// ── InventoryEntry ────────────────────────────────────────────────────────────

class InventoryEntry {
  final Product product;
  final int lowStockThreshold;

  const InventoryEntry({
    required this.product,
    this.lowStockThreshold = 5,
  });

  int get stock => product.stockQuantity;
  bool get isLowStock => stock <= lowStockThreshold && product.trackInventory;

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

  const InventoryState({
    this.entries = const [],
    this.loading = false,
    this.error,
    this.isOffline = false,
  });

  InventoryState copyWith({
    List<InventoryEntry>? entries,
    bool? loading,
    String? error,
    bool? isOffline,
  }) =>
      InventoryState(
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        error: error,
        isOffline: isOffline ?? this.isOffline,
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
    _load();
    _subscribeRealtime();
  }

  bool get _isOnline => _ref.read(isOnlineProvider);

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

  // ── Load — cache first, Supabase second ───────────────────────────────────

  Future<void> _load() async {
    state = state.copyWith(loading: true, error: null);

    // 1. Always serve SQLite cache immediately so UI is never blank
    try {
      final cached = await _local.getProducts(_businessId);
      if (cached.isNotEmpty) {
        state = state.copyWith(
          entries: cached.map((p) => InventoryEntry(product: p)).toList(),
          loading: true, // still loading — Supabase fetch pending
          isOffline: !_isOnline,
        );
      }
    } catch (e) {
      debugPrint('[Inventory] Cache read failed: $e');
    }

    // 2. If offline, stop here — use the cache
    if (!_isOnline) {
      state = state.copyWith(loading: false, isOffline: true);
      return;
    }

    // 3. Online: fetch from Supabase
    try {
      final rows = await _client
          .from('products')
          .select('*, categories(name)')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('name');

      final config = await _client
          .from('business_configs')
          .select('low_stock_threshold')
          .eq('business_id', _businessId)
          .maybeSingle();

      final threshold = (config?['low_stock_threshold'] as int?) ?? 5;

      final products = (rows as List)
          .map((row) => Product.fromMap(row as Map<String, dynamic>))
          .toList();

      // Write-through to SQLite cache
      await _local.upsertProducts(products);

      final entries = products
          .map((p) => InventoryEntry(product: p, lowStockThreshold: threshold))
          .toList();

      state = state.copyWith(
        entries: entries,
        loading: false,
        isOffline: false,
      );
    } catch (e, stack) {
      debugPrint('[Inventory] Supabase load failed: $e\n$stack');
      // Don't wipe existing entries — keep showing cache
      state = state.copyWith(
        loading: false,
        error: _isOnline ? e.toString() : null,
        isOffline: !_isOnline,
      );
    }
  }

  Future<void> refresh() => _load();

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

    // Optimistic update
    _updateEntry(index, entry.copyWith(
      product: entry.product.copyWith(stockQuantity: after),
    ));

    // Always update SQLite immediately
    await _local.updateProductStock(productId, after);

    if (_isOnline) {
      try {
        await _writeStockUpdate(
          productId: productId,
          newQty: after,
          before: before,
          after: after,
          action: action,
          notes: notes,
        );
      } catch (e) {
        debugPrint('[Inventory] Online write failed, queuing: $e');
        await _queueStockUpdate(
          productId: productId,
          delta: delta,
          action: action,
          notes: notes,
        );
      }
    } else {
      // Offline — queue for sync
      await _queueStockUpdate(
        productId: productId,
        delta: delta,
        action: action,
        notes: notes,
      );
    }
  }

  // ── Set stock ─────────────────────────────────────────────────────────────

  Future<void> setStock(String productId, int value, {String? notes}) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;

    final entry = state.entries[index];
    final before = entry.stock;
    final after = value.clamp(0, 9999);
    final delta = after - before;

    _updateEntry(index, entry.copyWith(
      product: entry.product.copyWith(stockQuantity: after),
    ));

    await _local.updateProductStock(productId, after);

    if (_isOnline) {
      try {
        await _writeStockUpdate(
          productId: productId,
          newQty: after,
          before: before,
          after: after,
          action: 'adjustment',
          notes: notes ?? 'Manual stock set',
        );
      } catch (e) {
        debugPrint('[Inventory] Online set failed, queuing: $e');
        await _queueStockUpdate(
          productId: productId,
          delta: delta,
          action: 'adjustment',
          notes: notes ?? 'Manual stock set',
        );
      }
    } else {
      await _queueStockUpdate(
        productId: productId,
        delta: delta,
        action: 'adjustment',
        notes: notes ?? 'Manual stock set',
      );
    }
  }

  // ── Toggle availability ───────────────────────────────────────────────────

  Future<void> toggleAvailability(String productId) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;

    final entry = state.entries[index];
    final newVal = !entry.product.isAvailable;

    _updateEntry(index, entry.copyWith(
      product: entry.product.copyWith(isAvailable: newVal),
    ));

    if (_isOnline) {
      try {
        await _client.from('products').update({
          'is_available': newVal,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', productId);
      } catch (e) {
        _updateEntry(index, entry); // rollback
        state = state.copyWith(error: 'Failed to update availability: $e');
      }
    }
    // Offline: optimistic only — no queue needed (non-critical)
  }

  Future<void> restock(String productId, int quantity, {String? notes}) =>
      adjustStock(productId, quantity,
          action: 'restock', notes: notes ?? 'Restock');

  // ── Private helpers ───────────────────────────────────────────────────────

  void _updateEntry(int index, InventoryEntry updated) {
    final list = List<InventoryEntry>.from(state.entries);
    list[index] = updated;
    state = state.copyWith(entries: list);
  }

  Future<void> _writeStockUpdate({
    required String productId,
    required int newQty,
    required int before,
    required int after,
    required String action,
    String? notes,
  }) async {
    await Future.wait([
      _client.from('products').update({
        'stock_quantity': newQty,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', productId),
      _client.from('inventory_logs').insert({
        'business_id': _businessId,
        'product_id': productId,
        'action': action,
        'quantity_change': after - before,
        'quantity_before': before,
        'quantity_after': after,
        'performed_by': _client.auth.currentUser?.id,
        'notes': notes,
      }),
    ]);
  }

  Future<void> _queueStockUpdate({
    required String productId,
    required int delta,
    required String action,
    String? notes,
  }) async {
    await _syncQueue.enqueue(
      operation: 'adjust_stock',
      tableName: 'products',
      recordId: productId,
      payload: {
        'business_id': _businessId,
        'quantity_change': delta,
        'action': action,
        'performed_by': _client.auth.currentUser?.id,
        'notes': notes,
      },
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final inventoryProvider =
    StateNotifierProvider<InventoryNotifier, InventoryState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final profile = ref.watch(profileProvider).asData?.value;
  final businessId = profile?.businessId ?? '';
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