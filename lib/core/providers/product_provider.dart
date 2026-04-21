import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../../features/auth/auth_provider.dart';

// ── Raw async fetch ───────────────────────────────────────────────────────────

final productListProvider = FutureProvider<List<Product>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) return [];

  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from('products')
      .select('*, categories(name)')
      .eq('business_id', profile!.businessId!)
      .eq('is_active', true)
      .order('name');

  return (data as List)
      .map((m) => Product.fromMap(m as Map<String, dynamic>))
      .toList();
});

// ── Category list derived from loaded products ────────────────────────────────

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final categoryListProvider = Provider<List<String>>((ref) {
  final productsAsync = ref.watch(productListProvider);
  return productsAsync.asData?.value
          .map((p) => p.category)
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList() ??
      [];
});

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final productsAsync = ref.watch(productListProvider);
  final products = productsAsync.asData?.value ?? [];
  final category = ref.watch(selectedCategoryProvider);
  if (category == null) return products;
  return products.where((p) => p.category == category).toList();
});

// ── Realtime stream (optional — drop-in upgrade) ──────────────────────────────
// Uncomment to replace FutureProvider with live updates:
//
// final productStreamProvider = StreamProvider<List<Product>>((ref) async* {
//   final profile = await ref.watch(profileProvider.future);
//   if (profile?.businessId == null) { yield []; return; }
//   final client = ref.watch(supabaseClientProvider);
//   yield* client
//       .from('products')
//       .stream(primaryKey: ['id'])
//       .eq('business_id', profile!.businessId!)
//       .order('name')
//       .map((rows) => rows.map(Product.fromMap).toList());
// });

// ── Inventory update helper ───────────────────────────────────────────────────

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(ref.watch(supabaseClientProvider));
});

class InventoryService {
  final SupabaseClient _client;
  InventoryService(this._client);

  Future<void> adjustStock({
    required String businessId,
    required String productId,
    required int quantityChange,
    required int quantityBefore,
    required String action, // 'sale', 'restock', 'adjustment', 'waste'
    String? notes,
  }) async {
    final quantityAfter = quantityBefore + quantityChange;

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
  }
}