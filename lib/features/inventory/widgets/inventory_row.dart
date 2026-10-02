// features/inventory/widgets/inventory_row.dart
// Adaptive inventory row: table layout (tablet/desktop) or card layout (phone).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inventory_service.dart';
import '../../../shared/widgets/app_colors.dart';
import '../../inventory/widgets/add_product_dialog.dart';
import 'inventory_shared.dart';
import '../../../shared/widgets/marquee_text.dart';
import '../../../core/providers/staff_provider.dart';
import '../../../core/models/staff.dart';
import '../../../core/models/product_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TABLE HEADER (tablet / desktop only)
// ─────────────────────────────────────────────────────────────────────────────

class InventoryTableHeader extends StatelessWidget {
  const InventoryTableHeader({super.key});

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
          SizedBox(width: 144),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADAPTIVE ROW — picks table or card based on layout
// ─────────────────────────────────────────────────────────────────────────────

class InventoryRow extends ConsumerStatefulWidget {
  final InventoryEntry entry;
  final InventoryLayout layout;

  const InventoryRow(
      {super.key, required this.entry, required this.layout});

  @override
  ConsumerState<InventoryRow> createState() => _InventoryRowState();
}

class _InventoryRowState extends ConsumerState<InventoryRow> {
  bool _adjusting = false;

  Future<void> _adjust(int delta) async {
    if (_adjusting) return;
    setState(() => _adjusting = true);
    try {
      await ref
          .read(inventoryProvider.notifier)
          .adjustStock(widget.entry.product.id, delta);
    } catch (_) {} finally {
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
    final staff = ref.read(activeStaffProvider);
    final isOwner = staff?.role == StaffRole.owner;
    final currentStock = widget.entry.stock;
    final controller = TextEditingController(text: '$currentStock');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set stock — ${widget.entry.product.name}',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                helperText: isOwner
                    ? null
                    : 'Minimum: $currentStock (cannot reduce stock)',
                helperStyle: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
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
              if (v == null) return;
              if (!isOwner && v < currentStock) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Cannot reduce stock below $currentStock'),
                    backgroundColor: AppColors.danger,
                  ),
                );
                return;
              }
              _set(v);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  bool _expanded = false;
  String? _adjustingVariantId;

  Future<void> _adjustVariant(ProductVariant v, int delta) async {
    if (_adjustingVariantId != null) return;
    setState(() => _adjustingVariantId = v.id);
    try {
      await ref.read(inventoryProvider.notifier).adjustVariant(
            widget.entry.product.id,
            v.id,
            delta,
            action: delta > 0 ? 'restock' : 'adjustment',
            notes: delta > 0 ? 'Restock' : 'Manual decrease',
          );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _adjustingVariantId = null);
    }
  }

  void _showSetVariantDialog(ProductVariant v) {
    final isOwner = ref.read(activeStaffProvider)?.role == StaffRole.owner;
    final current = v.stockQuantity;
    final controller = TextEditingController(text: '$current');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set stock — ${widget.entry.product.name} (${v.name})',
            style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Quantity',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            helperText:
                isOwner ? null : 'Minimum: $current (cannot reduce stock)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n == null) return;
              if (!isOwner && n < current) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Cannot reduce stock below $current'),
                  backgroundColor: AppColors.danger,
                ));
                return;
              }
              ref.read(inventoryProvider.notifier).setVariantStock(
                  widget.entry.product.id, v.id, n);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProductDialog(product: widget.entry.product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(activeStaffProvider);
    final isOwner = staff?.role == StaffRole.owner;

    if (widget.entry.product.hasVariants) {
      final phone = widget.layout == InventoryLayout.phone;
      final p = widget.entry.product;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VariantParentRow(
            entry: widget.entry,
            phone: phone,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            onEdit: _showEditDialog,
          ),
          if (_expanded)
            for (final v in p.activeVariants)
              _VariantStockRow(
                variant: v,
                price: p.priceForVariant(v),
                threshold: widget.entry.lowStockThreshold,
                phone: phone,
                isOwner: isOwner,
                busy: _adjustingVariantId == v.id,
                onAdjust: (d) => _adjustVariant(v, d),
                onSet: () => _showSetVariantDialog(v),
              ),
        ],
      );
    }

    return widget.layout == InventoryLayout.phone
        ? _PhoneCard(
            entry: widget.entry,
            adjusting: _adjusting,
            onAdjust: _adjust,
            onSet: _showSetDialog,
            onEdit: _showEditDialog,
            isOwner: isOwner,
          )
        : _TableRow(
            entry: widget.entry,
            adjusting: _adjusting,
            onAdjust: _adjust,
            onSet: _showSetDialog,
            onEdit: _showEditDialog,
            isOwner: isOwner,
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PHONE CARD LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneCard extends StatelessWidget {
  final InventoryEntry entry;
  final bool adjusting;
  final bool isOwner;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSet;
  final VoidCallback onEdit;

  const _PhoneCard({
    required this.entry,
    required this.adjusting,
    required this.isOwner,
    required this.onAdjust,
    required this.onSet,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = entry.isLowStock;
    final isOut = entry.stock == 0;
    final stockColor = isOut
        ? AppColors.danger
        : isLow
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              isLow ? AppColors.danger.withValues(alpha:0.25) : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: name + category + price ─────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.product.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (entry.product.barcode != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.product.barcode!,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppColors.textSecondary.withValues(alpha:0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${entry.product.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        entry.product.category,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Stock row ─────────────────────────────────────────────
            Row(
              children: [
                // Stock status pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: stockColor.withValues(alpha:0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOut
                            ? Icons.remove_circle_outline_rounded
                            : isLow
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 12,
                        color: stockColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOut ? 'Out' : isLow ? 'Low' : 'OK',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: stockColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Minus — owner only
                StepperButton(
                  icon: Icons.remove,
                  onTap: (isOwner && !adjusting) ? () => onAdjust(-1) : null,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: adjusting
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          '${entry.stock}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isLow
                                ? AppColors.danger
                                : AppColors.textPrimary,
                          ),
                        ),
                ),
                const SizedBox(width: 8),

                // Plus — all roles
                StepperButton(
                  icon: Icons.add,
                  onTap: adjusting ? null : () => onAdjust(1),
                  positive: true,
                ),

                const Spacer(),

                // Set — all roles (min enforced inside dialog)
                TextButton(
                  onPressed: onSet,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Set',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),

                // Edit — all roles (min enforced inside dialog)
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Edit',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLET / DESKTOP TABLE ROW
// ─────────────────────────────────────────────────────────────────────────────

class _TableRow extends StatelessWidget {
  final InventoryEntry entry;
  final bool adjusting;
  final bool isOwner;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSet;
  final VoidCallback onEdit;

  const _TableRow({
    required this.entry,
    required this.adjusting,
    required this.isOwner,
    required this.onAdjust,
    required this.onSet,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = entry.isLowStock;

    return Container(
      color: isLow ? AppColors.danger.withValues(alpha:0.03) : null,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Product name + barcode
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
                      MarqueeText(
                        text: entry.product.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      if (entry.product.barcode != null)
                        MarqueeText(
                          text: entry.product.barcode!,
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color:
                                  AppColors.textSecondary.withValues(alpha:0.7)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Category
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
                child: MarqueeText(
                  text: entry.product.category,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
          ),

          // Price
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

          // Stock stepper
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // Minus — owner only
                StepperButton(
                  icon: Icons.remove,
                  onTap: (isOwner && !adjusting) ? () => onAdjust(-1) : null,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 32,
                  child: adjusting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
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

                // Plus — all roles
                StepperButton(
                  icon: Icons.add,
                  onTap: adjusting ? null : () => onAdjust(1),
                  positive: true,
                ),
              ],
            ),
          ),

          // Set — all roles (min enforced inside dialog)
          SizedBox(
            width: 72,
            child: TextButton(
              onPressed: onSet,
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

          // Edit — all roles (min enforced inside dialog)
          SizedBox(
            width: 72,
            child: TextButton(
              onPressed: onEdit,
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
// ─────────────────────────────────────────────────────────────────────────────
// VARIANT PARENT ROW + VARIANT STOCK ROW
// ─────────────────────────────────────────────────────────────────────────────

class _VariantParentRow extends StatelessWidget {
  final InventoryEntry entry;
  final bool phone;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _VariantParentRow({
    required this.entry,
    required this.phone,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = entry.product;
    final vs = p.activeVariants;
    final out = vs.where((v) => v.stockQuantity <= 0).length;
    final low = vs
        .where((v) =>
            v.stockQuantity > 0 && v.stockQuantity <= entry.lowStockThreshold)
        .length;
    final prices = vs.map((v) => p.priceForVariant(v)).toList()..sort();
    final priceText = prices.first == prices.last
        ? '₱${prices.first.toStringAsFixed(0)}'
        : '₱${prices.first.toStringAsFixed(0)}–${prices.last.toStringAsFixed(0)}';

    Widget? badge;
    if (out > 0 || low > 0) {
      final c = out > 0 ? AppColors.danger : const Color(0xFFF59E0B);
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(out > 0 ? '$out out' : '$low low',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: c)),
      );
    }

    final chevron = Icon(
        expanded ? Icons.expand_less : Icons.expand_more,
        size: 18,
        color: AppColors.textSecondary);

    final nameCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        Text('${vs.length} variants',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );

    final editBtn = TextButton(
      onPressed: onEdit,
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      child: const Text('Edit',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );

    if (phone) {
      return InkWell(
        onTap: onToggle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              chevron,
              const SizedBox(width: 8),
              Expanded(child: nameCol),
              if (badge != null) ...[badge, const SizedBox(width: 8)],
              Text('${entry.stock}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              editBtn,
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(children: [
                chevron,
                const SizedBox(width: 8),
                Expanded(child: nameCol),
              ]),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(p.category,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary)),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(priceText,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            Expanded(
              flex: 3,
              child: Row(children: [
                Text('${entry.stock}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                const Text('total',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                if (badge != null) ...[const SizedBox(width: 8), badge],
              ]),
            ),
            const SizedBox(width: 72),
            SizedBox(width: 72, child: editBtn),
          ],
        ),
      ),
    );
  }
}

class _VariantStockRow extends StatelessWidget {
  final ProductVariant variant;
  final double price;
  final int threshold;
  final bool phone;
  final bool isOwner;
  final bool busy;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSet;

  const _VariantStockRow({
    required this.variant,
    required this.price,
    required this.threshold,
    required this.phone,
    required this.isOwner,
    required this.busy,
    required this.onAdjust,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final q = variant.stockQuantity;
    final color = q <= 0
        ? AppColors.danger
        : q <= threshold
            ? const Color(0xFFF59E0B)
            : AppColors.textPrimary;

    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(phone ? 32 : 56, 8, phone ? 16 : 24, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(variant.name,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
          Text('₱${price.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          StepperButton(
            icon: Icons.remove,
            onTap: (isOwner && !busy) ? () => onAdjust(-1) : null,
          ),
          SizedBox(
            width: 44,
            child: busy
                ? const Center(
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Text('$q',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color)),
          ),
          StepperButton(
            icon: Icons.add,
            onTap: busy ? null : () => onAdjust(1),
            positive: true,
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onSet,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Set',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}