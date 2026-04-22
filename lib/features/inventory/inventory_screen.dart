import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'inventory_service.dart';
import '../../shared/widgets/app_colors.dart';
import 'widgets/add_product_dialog.dart';

final _searchQueryProvider = StateProvider<String>((ref) => '');

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryState = ref.watch(inventoryProvider);
    final query = ref.watch(_searchQueryProvider).toLowerCase();

    // ── Loading ──────────────────────────────────────────────────────────────
    if (inventoryState.loading) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // ── Error ────────────────────────────────────────────────────────────────
    if (inventoryState.error != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(inventoryState.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger)),
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

    // ── Data ─────────────────────────────────────────────────────────────────
    final entries = inventoryState.entries;
    final lowCount = inventoryState.lowStockItems.length;

    final filtered = query.isEmpty
        ? entries
        : entries
            .where((e) =>
                e.product.name.toLowerCase().contains(query) ||
                e.product.category.toLowerCase().contains(query) ||
                (e.product.barcode?.contains(query) ?? false))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    _StatPill(
                      label: 'Total SKUs',
                      value: '${entries.length}',
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    if (lowCount > 0)
                      _StatPill(
                        label: 'Low Stock',
                        value: '$lowCount',
                        color: AppColors.danger,
                      ),
                    const SizedBox(width: 8),
                    // ── Add product button ──────────────────────────
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
                const SizedBox(height: 16),

                // ── Search bar ──────────────────────────────────────────────
                Container(
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
                              .read(_searchQueryProvider.notifier)
                              .state = v,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText:
                                'Search by name, category or barcode…',
                            hintStyle: TextStyle(
                                color:
                                    AppColors.textSecondary.withOpacity(0.6),
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
                const SizedBox(height: 16),
                const _TableHeader(),
              ],
            ),
          ),

          // ── Low-stock banner ────────────────────────────────────────────────
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

          // ── Error inline banner ─────────────────────────────────────────────
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

          // ── Table body ──────────────────────────────────────────────────────
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
                          query.isEmpty
                              ? 'No products found'
                              : 'No results for "$query"',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 24, endIndent: 24),
                    itemBuilder: (context, index) =>
                        _InventoryRow(entry: filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Table header ──────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.6);
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('PRODUCT', style: style)),
          Expanded(flex: 2, child: Text('CATEGORY', style: style)),
          Expanded(flex: 2, child: Text('PRICE', style: style)),
          Expanded(flex: 3, child: Text('STOCK', style: style)),
          SizedBox(width: 144), // wider to accommodate Set + Edit buttons
        ],
      ),
    );
  }
}

// ── Inventory row ─────────────────────────────────────────────────────────────

class _InventoryRow extends ConsumerStatefulWidget {
  final InventoryEntry entry;
  const _InventoryRow({required this.entry});

  @override
  ConsumerState<_InventoryRow> createState() => _InventoryRowState();
}

class _InventoryRowState extends ConsumerState<_InventoryRow> {
  bool _adjusting = false;

  Future<void> _adjust(int delta) async {
    if (_adjusting) return;
    setState(() => _adjusting = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .adjustStock(widget.entry.product.id, delta);
    } catch (_) {}
    finally {
      if (mounted) setState(() => _adjusting = false);
    }
  }

  Future<void> _set(int value) async {
    try {
      await ref
          .read(inventoryProvider.notifier)
          .setStock(widget.entry.product.id, value);
    } catch (_) {}
  }

  void _showSetDialog() {
    final controller =
        TextEditingController(text: '${widget.entry.stock}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set stock — ${widget.entry.product.name}',
            style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Quantity',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.inventory_2_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v != null) _set(v);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isLow = entry.isLowStock;

    return Container(
      color: isLow ? AppColors.danger.withOpacity(0.03) : null,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // ── Name + barcode ────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Row(
              children: [
                if (isLow)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: AppColors.danger, shape: BoxShape.circle),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.product.name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      if (entry.product.barcode != null)
                        Text(entry.product.barcode!,
                            style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: AppColors.textSecondary
                                    .withOpacity(0.7))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Category ──────────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(entry.product.category,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary)),
              ),
            ),
          ),

          // ── Price ─────────────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Text(
              '₱${entry.product.price.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),

          // ── Stepper ───────────────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  onTap: _adjusting ? null : () => _adjust(-1),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 32,
                  child: _adjusting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '${entry.stock}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isLow
                                ? AppColors.danger
                                : AppColors.textPrimary,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                _StepperButton(
                  icon: Icons.add,
                  onTap: _adjusting ? null : () => _adjust(1),
                  positive: true,
                ),
              ],
            ),
          ),

          // ── Set button ────────────────────────────────────────────────────
          SizedBox(
            width: 72,
            child: TextButton(
              onPressed: _showSetDialog,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Set',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),

          // ── Edit button ───────────────────────────────────────────────────
          SizedBox(
            width: 72,
            child: TextButton(
              onPressed: () => showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => AddProductDialog(product: entry.product),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Edit',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stepper button ────────────────────────────────────────────────────────────

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool positive;

  const _StepperButton(
      {required this.icon, required this.onTap, this.positive = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: !enabled
              ? AppColors.divider
              : positive
                  ? AppColors.primary.withOpacity(0.08)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon,
            size: 14,
            color: !enabled
                ? AppColors.textSecondary.withOpacity(0.3)
                : positive
                    ? AppColors.primary
                    : AppColors.textSecondary),
      ),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
        ],
      ),
    );
  }
}