// lib/features/pos/dialogs/variant_picker_dialog.dart
//
// Shown in the POS when a user taps a product that has variants.
// Returns the selected [ProductVariant] via Navigator.pop(variant).

import 'package:flutter/material.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../shared/widgets/app_colors.dart';

class VariantPickerDialog extends StatefulWidget {
  final Product product;

  const VariantPickerDialog({super.key, required this.product});

  /// Convenience helper — returns the chosen variant or null if cancelled.
  static Future<ProductVariant?> show(
    BuildContext context,
    Product product,
  ) {
    return showDialog<ProductVariant>(
      context: context,
      builder: (_) => VariantPickerDialog(product: product),
    );
  }

  @override
  State<VariantPickerDialog> createState() => _VariantPickerDialogState();
}

class _VariantPickerDialogState extends State<VariantPickerDialog> {
  ProductVariant? _selected;

  Product get product => widget.product;

  // Group variants by option_type so we can show labelled sections
  Map<String, List<ProductVariant>> get _grouped {
    final map = <String, List<ProductVariant>>{};
    for (final v in product.activeVariants) {
      final key = (v.optionType?.isNotEmpty == true) ? v.optionType! : 'Options';
      map.putIfAbsent(key, () => []);
      map[key]!.add(v);
    }
    return map;
  }

  bool get _hasGroups => _grouped.length > 1;

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.style_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Select a variant',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha:0.75),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Variant list ─────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in grouped.entries) ...[
                      if (_hasGroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 6, top: 4),
                          child: Text(
                            _capitalize(entry.key),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5),
                          ),
                        ),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value
                            .map((v) => _VariantChip(
                                  variant: v,
                                  basePrice: product.price,
                                  isSelected: _selected?.id == v.id,
                                  onTap: product.trackInventory &&
                                          v.stockQuantity <= 0
                                      ? null // disabled when out of stock
                                      : () =>
                                          setState(() => _selected = v),
                                ))
                            .toList(),
                      ),
                      if (entry.key != grouped.keys.last)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // ── Confirm button ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // Selected variant price preview
                  if (_selected != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha:0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            _selected!.name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                          const Spacer(),
                          Text(
                            '₱${product.priceForVariant(_selected!).toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.divider,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _selected == null
                            ? 'Select a variant'
                            : 'Add to Cart — ₱${product.priceForVariant(_selected!).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Variant chip ──────────────────────────────────────────────────────────────

class _VariantChip extends StatelessWidget {
  final ProductVariant variant;
  final double basePrice;
  final bool isSelected;
  final VoidCallback? onTap; // null = disabled (out of stock)

  const _VariantChip({
    required this.variant,
    required this.basePrice,
    required this.isSelected,
    this.onTap,
  });

  bool get _outOfStock => onTap == null;

  @override
  Widget build(BuildContext context) {
    final resolvedPrice = variant.resolvedPrice(basePrice);
    final deltaLabel = variant.priceDelta == 0
        ? null
        : variant.priceDelta > 0
            ? '+₱${variant.priceDelta.toStringAsFixed(2)}'
            : '−₱${variant.priceDelta.abs().toStringAsFixed(2)}';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _outOfStock
              ? AppColors.surface
              : isSelected
                  ? AppColors.primary
                  : Colors.white,
          border: Border.all(
            color: _outOfStock
                ? AppColors.divider
                : isSelected
                    ? AppColors.primary
                    : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Variant name
            Text(
              variant.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _outOfStock
                    ? AppColors.textSecondary
                    : isSelected
                        ? Colors.white
                        : AppColors.textPrimary,
                decoration: _outOfStock
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),

            const SizedBox(height: 2),

            // Price + delta
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₱${resolvedPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _outOfStock
                        ? AppColors.textSecondary
                        : isSelected
                            ? Colors.white70
                            : AppColors.textSecondary,
                  ),
                ),
                if (deltaLabel != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    deltaLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: _outOfStock
                          ? AppColors.textSecondary
                          : isSelected
                              ? Colors.white60
                              : variant.priceDelta > 0
                                  ? Colors.green.shade600
                                  : Colors.red.shade400,
                    ),
                  ),
                ],
              ],
            ),

            // Out of stock badge
            if (_outOfStock) ...[
              const SizedBox(height: 3),
              Text(
                'Out of stock',
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}