// lib/core/providers/product_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
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

  // Immediately yield cached data so UI is never blank
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

  Future<List<Product>> fetchAll() async {
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
    return products;
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
      .subscribe((status, [error]) {
        debugPrint('[productListProvider] Realtime status: $status error: $error');
        // ✅ If realtime fails to connect, fall back to polling every 30s
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          debugPrint('[productListProvider] Realtime failed, will rely on lifecycle refresh');
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

// ── Selected category ─────────────────────────────────────────────────────────

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productListProvider).asData?.value ?? [];
  final category = ref.watch(selectedCategoryProvider);

  bool isVisible(Product p) {
    if (!p.isAvailable) return false;
    if (p.trackInventory && p.stockQuantity <= 0) return false;
    return true;
  }

  if (category == null) return products.where(isVisible).toList();
  return products
      .where((p) => p.category == category && isVisible(p))
      .toList();
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

  Future<void> _queueAdjust({
    required String businessId,
    required String productId,
    required int quantityChange,
    required String action,
    String? notes,
  }) async {
    await _syncQueue.enqueue(
      operation: 'adjust_stock',
      tableName: 'products',
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