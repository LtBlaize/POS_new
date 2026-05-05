// features/inventory/widgets/inventory_row.dart
// Adaptive inventory row: table layout (tablet/desktop) or card layout (phone).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inventory_service.dart';
import '../../../shared/widgets/app_colors.dart';
import '../../inventory/widgets/add_product_dialog.dart';
import 'inventory_shared.dart';
import'../../../shared/widgets/marquee_text.dart';

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
    final controller =
        TextEditingController(text: '${widget.entry.stock}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set stock — ${widget.entry.product.name}',
            style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Quantity',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
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

  void _showEditDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProductDialog(product: widget.entry.product),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.layout == InventoryLayout.phone
        ? _PhoneCard(
            entry: widget.entry,
            adjusting: _adjusting,
            onAdjust: _adjust,
            onSet: _showSetDialog,
            onEdit: _showEditDialog,
          )
        : _TableRow(
            entry: widget.entry,
            adjusting: _adjusting,
            onAdjust: _adjust,
            onSet: _showSetDialog,
            onEdit: _showEditDialog,
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PHONE CARD LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneCard extends StatelessWidget {
  final InventoryEntry entry;
  final bool adjusting;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSet;
  final VoidCallback onEdit;

  const _PhoneCard({
    required this.entry,
    required this.adjusting,
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
          color: isLow ? AppColors.danger.withOpacity(0.25) : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                            color:
                                AppColors.textSecondary.withOpacity(0.7),
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
                    color: stockColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: stockColor.withOpacity(0.3)),
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

                // Stepper
                StepperButton(
                  icon: Icons.remove,
                  onTap: adjusting ? null : () => onAdjust(-1),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: adjusting
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
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
                StepperButton(
                  icon: Icons.add,
                  onTap: adjusting ? null : () => onAdjust(1),
                  positive: true,
                ),

                const Spacer(),

                // Actions
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
  final ValueChanged<int> onAdjust;
  final VoidCallback onSet;
  final VoidCallback onEdit;

  const _TableRow({
    required this.entry,
    required this.adjusting,
    required this.onAdjust,
    required this.onSet,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = entry.isLowStock;

    return Container(
      color: isLow ? AppColors.danger.withOpacity(0.03) : null,
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
                          color: AppColors.danger,
                          shape: BoxShape.circle),
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
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
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
                child: // after
                MarqueeText(
                  text: entry.product.category,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
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
                StepperButton(
                  icon: Icons.remove,
                  onTap: adjusting ? null : () => onAdjust(-1),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 32,
                  child: adjusting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
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
                StepperButton(
                  icon: Icons.add,
                  onTap: adjusting ? null : () => onAdjust(1),
                  positive: true,
                ),
              ],
            ),
          ),

          // Actions
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
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
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
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}