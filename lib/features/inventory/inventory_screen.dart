// lib/features/inventory/inventory_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'inventory_service.dart';
import '../../shared/widgets/app_colors.dart';
import 'widgets/add_product_dialog.dart';
import 'widgets/inventory_shared.dart';
import 'widgets/inventory_filter.dart';
import 'widgets/inventory_row.dart';

// ── Filter state provider ─────────────────────────────────────────────────────

final _filterProvider =
    StateProvider<InventoryFilterState>((ref) => const InventoryFilterState());

// ── Screen ────────────────────────────────────────────────────────────────────

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryState = ref.watch(inventoryProvider);
    final filter = ref.watch(_filterProvider);
    final layout = inventoryLayoutOf(context);

    if (inventoryState.loading) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (inventoryState.error != null && inventoryState.entries.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              const Text('Offline — no cached inventory yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(inventoryProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final entries = inventoryState.entries;
    final lowCount = inventoryState.lowStockItems.length;

    final categories = entries
        .map((e) => e.product.category)
        .toSet()
        .toList()
      ..sort();

    final filtered = _applyFilters(entries, filter);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (layout == InventoryLayout.phone) ...[
                  // ── Phone: row 1 — title + stats ──────────────
                  Row(
                    children: [
                      const Text(
                        'Inventory',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      StatPill(
                        label: 'SKUs',
                        value: '${entries.length}',
                        color: AppColors.primary,
                      ),
                      if (lowCount > 0) ...[
                        const SizedBox(width: 6),
                        StatPill(
                          label: 'Low',
                          value: '$lowCount',
                          color: AppColors.danger,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Phone: row 2 — add + refresh ──────────────
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const AddProductDialog(),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Product',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () =>
                            ref.read(inventoryProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh,
                            size: 18, color: AppColors.textSecondary),
                        tooltip: 'Refresh',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // ── Tablet/desktop: single row ─────────────────
                  Row(
                    children: [
                      const Text(
                        'Inventory',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      StatPill(
                        label: 'Total SKUs',
                        value: '${entries.length}',
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      if (lowCount > 0) ...[
                        StatPill(
                          label: 'Low Stock',
                          value: '$lowCount',
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: () => showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const AddProductDialog(),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Product',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () =>
                            ref.read(inventoryProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh,
                            size: 18, color: AppColors.textSecondary),
                        tooltip: 'Refresh',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
  

                // Search + filter row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(Icons.search,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                onChanged: (v) => ref
                                    .read(_filterProvider.notifier)
                                    .state = ref
                                    .read(_filterProvider)
                                    .copyWith(search: v),
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search by name, category or barcode…',
                                  hintStyle: TextStyle(
                                      color: AppColors.textSecondary
                                          .withOpacity(0.6),
                                      fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterButton(
                      filter: filter,
                      categories: categories,
                      entries: entries,
                      onChanged: (f) =>
                          ref.read(_filterProvider.notifier).state = f,
                    ),
                    const SizedBox(width: 8),
                    SortButton(
                      sort: filter.sort,
                      onChanged: (s) => ref
                          .read(_filterProvider.notifier)
                          .state = filter.copyWith(sort: s),
                    ),
                    if (filter.hasActiveFilters) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Clear all filters',
                        child: IconButton(
                          onPressed: () => ref
                              .read(_filterProvider.notifier)
                              .state = const InventoryFilterState(),
                          icon: const Icon(Icons.filter_alt_off_outlined,
                              size: 18, color: AppColors.danger),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AppColors.danger.withOpacity(0.07),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                ActiveFilterChips(
                  filter: filter,
                  onChanged: (f) =>
                      ref.read(_filterProvider.notifier).state = f,
                ),

                const SizedBox(height: 8),
                // Table header only on tablet/desktop
                if (layout != InventoryLayout.phone)
                  const InventoryTableHeader(),
              ],
            ),
          ),

          // ── Low stock banner ───────────────────────────────────────
          if (lowCount > 0)
            Container(
              color: AppColors.danger.withOpacity(0.06),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: AppColors.danger, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$lowCount item${lowCount > 1 ? 's' : ''} running low — reorder soon.',
                    style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          if (inventoryState.error != null)
            Container(
              color: AppColors.danger.withOpacity(0.08),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(inventoryState.error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(inventoryProvider.notifier).refresh(),
                    child: const Text('Retry',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
            ),

          // ── Results count ─────────────────────────────────────────
          if (filter.hasActiveFilters)
            Container(
              color: AppColors.primary.withOpacity(0.04),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.filter_list_rounded,
                      size: 14,
                      color: AppColors.primary.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'Showing ${filtered.length} of ${entries.length} products',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary.withOpacity(0.7),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          // ── List ──────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 48,
                            color: AppColors.textSecondary.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        Text(
                          filter.hasActiveFilters
                              ? 'No products match the current filters'
                              : 'No products found',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                        if (filter.hasActiveFilters) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => ref
                                .read(_filterProvider.notifier)
                                .state = const InventoryFilterState(),
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => layout == InventoryLayout.phone
                        ? const SizedBox.shrink()
                        : const Divider(height: 1, indent: 24, endIndent: 24),
                    itemBuilder: (context, index) => InventoryRow(
                      entry: filtered[index],
                      layout: layout,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Filter logic (pure, no widgets) ──────────────────────────────────────────

List<InventoryEntry> _applyFilters(
    List<InventoryEntry> entries, InventoryFilterState f) {
  var list = entries.where((e) {
    if (f.search.isNotEmpty) {
      final q = f.search.toLowerCase();
      final match = e.product.name.toLowerCase().contains(q) ||
          e.product.category.toLowerCase().contains(q) ||
          (e.product.barcode?.contains(q) ?? false);
      if (!match) return false;
    }

    if (f.category != null && e.product.category != f.category) return false;

    switch (f.stockFilter) {
      case StockFilter.out:
        if (e.stock > 0) return false;
      case StockFilter.low:
        if (!e.isLowStock || e.stock == 0) return false;
      case StockFilter.ok:
        if (e.isLowStock || e.stock == 0) return false;
      case StockFilter.all:
        break;
    }

    if (f.minPrice != null && e.product.price < f.minPrice!) return false;
    if (f.maxPrice != null && e.product.price > f.maxPrice!) return false;

    return true;
  }).toList();

  list.sort((a, b) => switch (f.sort) {
        SortOrder.nameAsc => a.product.name.compareTo(b.product.name),
        SortOrder.nameDesc => b.product.name.compareTo(a.product.name),
        SortOrder.priceAsc => a.product.price.compareTo(b.product.price),
        SortOrder.priceDesc => b.product.price.compareTo(a.product.price),
        SortOrder.stockAsc => a.stock.compareTo(b.stock),
        SortOrder.stockDesc => b.stock.compareTo(a.stock),
      });

  return list;
}