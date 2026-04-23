import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/product.dart';
import '../../features/auth/auth_provider.dart';

// ── InventoryEntry ────────────────────────────────────────────────────────────

class InventoryEntry {
  final Product product;
  final int lowStockThreshold;

  const InventoryEntry({
    required this.product,
    this.lowStockThreshold = 5,
  });

  // Stock is read directly from product.stockQuantity — single source of truth
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

  const InventoryState({
    this.entries = const [],
    this.loading = false,
    this.error,
  });

  InventoryState copyWith({
    List<InventoryEntry>? entries,
    bool? loading,
    String? error,
  }) =>
      InventoryState(
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        error: error,             // null clears the error
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
  RealtimeChannel? _channel; // ← add this

  InventoryNotifier({
    required SupabaseClient client,
    required String businessId,
  })  : _client = client,
        _businessId = businessId,
        super(const InventoryState(loading: true)) {
    _load();
    _subscribeRealtime(); // ← add this
  }

  // ── Realtime subscription ─────────────────────────────────────────────────

  void _subscribeRealtime() {
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
            _load(); // re-fetch on any INSERT, UPDATE, DELETE
          },
        )
        .subscribe();
  }

  // ── Dispose: unsubscribe on provider teardown ─────────────────────────────

  @override
  void dispose() {
    _client.removeChannel(_channel!);
    super.dispose();
  }

  // ... rest of your existing methods unchanged


  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final rows = await _client
          .from('products')
          .select('*, categories(name)')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('name');

      // Fetch the business config for low_stock_threshold
      final config = await _client
          .from('business_configs')
          .select('low_stock_threshold')
          .eq('business_id', _businessId)
          .maybeSingle();

      final threshold = (config?['low_stock_threshold'] as int?) ?? 5;

      final entries = (rows as List)
          .map((row) => InventoryEntry(
                product: Product.fromMap(row as Map<String, dynamic>),
                lowStockThreshold: threshold,
              ))
          .toList();

      state = state.copyWith(entries: entries, loading: false);
    } catch (e, stack) {
      debugPrint('InventoryNotifier._load error: $e\n$stack');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refresh() => _load();

  // ── Adjust stock (±delta) ─────────────────────────────────────────────────

  Future<void> adjustStock(
    String productId,
    int delta, {
    String action = 'adjustment', // 'restock' | 'adjustment' | 'waste'
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
      // Roll back on failure
      _updateEntry(index, entry);
      state = state.copyWith(error: 'Failed to adjust stock: $e');
      debugPrint('adjustStock error: $e');
      rethrow;
    }
  }

  // ── Set stock (absolute value) ────────────────────────────────────────────

  Future<void> setStock(
    String productId,
    int value, {
    String? notes,
  }) async {
    final index = state.entries.indexWhere((e) => e.product.id == productId);
    if (index < 0) return;

    final entry = state.entries[index];
    final before = entry.stock;
    final after = value.clamp(0, 9999);

    _updateEntry(index, entry.copyWith(
      product: entry.product.copyWith(stockQuantity: after),
    ));

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
      _updateEntry(index, entry);
      state = state.copyWith(error: 'Failed to set stock: $e');
      debugPrint('setStock error: $e');
      rethrow;
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

    try {
      await _client
          .from('products')
          .update({
            'is_available': newVal,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', productId);
    } catch (e) {
      _updateEntry(index, entry);
      state = state.copyWith(error: 'Failed to update availability: $e');
      rethrow;
    }
  }

  // ── Restock helper (common shortcut) ─────────────────────────────────────

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
    // Run both writes; if either fails the caller rolls back the UI
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
}

// ── Provider ──────────────────────────────────────────────────────────────────

final inventoryProvider =
    StateNotifierProvider<InventoryNotifier, InventoryState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final profile = ref.watch(profileProvider).asData?.value;
  final businessId = profile?.businessId ?? '';

  return InventoryNotifier(client: client, businessId: businessId);
});

// Convenience derived providers
final lowStockProvider = Provider<List<InventoryEntry>>((ref) {
  return ref.watch(inventoryProvider).lowStockItems;
});

final trackedInventoryProvider = Provider<List<InventoryEntry>>((ref) {
  return ref.watch(inventoryProvider).trackedItems;
});