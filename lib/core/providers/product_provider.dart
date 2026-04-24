// lib/core/providers/product_provider.dart
//
// Cache-first product list:
//   Online  → stream from Supabase, write-through to SQLite
//   Offline → read from SQLite cache
//
// Inventory adjustments are queued when offline and replayed on reconnect.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';

// ── Product list ──────────────────────────────────────────────────────────────

/// Cache-first product list. Always returns something, even offline.
final productListProvider = StreamProvider<List<Product>>((ref) async* {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) {
    yield [];
    return;
  }

  final businessId = profile!.businessId!;
  final local = ref.read(localDbServiceProvider);

  // Immediately yield cached data so the UI is never blank
  final cached = await local.getProducts(businessId);
  if (cached.isNotEmpty) yield cached;

  // If offline, wait until connectivity is restored before hitting Supabase
  if (!ref.read(isOnlineProvider)) {
    final completer = Completer<void>();
    final sub = ref.listen<bool>(isOnlineProvider, (_, next) {
      if (next && !completer.isCompleted) completer.complete();
    });
    await completer.future;
    sub.close();
  }

  // Online path: stream from Supabase and keep cache fresh
  final client = ref.watch(supabaseClientProvider);

  yield* client
      .from('products')
      .stream(primaryKey: ['id'])
      .eq('business_id', businessId)
      .order('name')
      .asyncMap((rows) async {
        final products = rows
            .map((m) => Product.fromMap(m))
            .where((p) => p.isActive)
            .toList();
        // Write-through to local cache
        await local.upsertProducts(products);
        return products;
      });
});

// ── Category filter ───────────────────────────────────────────────────────────

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final categoryListProvider = Provider<List<String>>((ref) {
  final products = ref.watch(productListProvider).asData?.value ?? [];
  return products
      .map((p) => p.category)
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList();
});

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productListProvider).asData?.value ?? [];
  final category = ref.watch(selectedCategoryProvider);
  if (category == null) return products;
  return products.where((p) => p.category == category).toList();
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

    // Always update local cache immediately
    await _local.updateProductStock(productId, quantityAfter);

    final isOnline = _ref.read(isOnlineProvider);

    if (isOnline) {
      try {
        await _client.from('products').update({
          'stock_quantity': quantityAfter,
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
      // Offline — queue for later
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