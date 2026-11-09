// lib/features/pos/dialogs/promo_choice_dialog.dart
import 'package:flutter/material.dart';

import '../../../core/models/product.dart';
import '../../../core/models/promo.dart';
import '../../../shared/widgets/app_colors.dart';

/// Lets the cashier fill a package's choice groups. Returns the chosen
/// products as components, or null if cancelled.
Future<List<PromoComponent>?> showPromoChoiceDialog({
  required BuildContext context,
  required Promo promo,
  required List<Product> liveProducts,
}) {
  return showDialog<List<PromoComponent>>(
    context: context,
    builder:
        (_) => _PromoChoiceDialog(promo: promo, liveProducts: liveProducts),
  );
}

class _PromoChoiceDialog extends StatefulWidget {
  final Promo promo;
  final List<Product> liveProducts;
  const _PromoChoiceDialog({required this.promo, required this.liveProducts});

  @override
  State<_PromoChoiceDialog> createState() => _PromoChoiceDialogState();
}

class _PromoChoiceDialogState extends State<_PromoChoiceDialog> {
  final Map<String, int> _counts = {}; // PromoItem.id -> how many picked

  Map<String, List<PromoItem>> get _groups {
    final m = <String, List<PromoItem>>{};
    for (final i in widget.promo.choiceItems) {
      m.putIfAbsent(i.choiceGroup ?? 'Choose', () => []).add(i);
    }
    return m;
  }

  int _picked(List<PromoItem> items) =>
      items.fold<int>(0, (s, i) => s + (_counts[i.id] ?? 0));

  int _need(List<PromoItem> items) => items.first.pickCount ?? 1;

  /// null = not stock-tracked (unlimited).
  int? _available(PromoItem i) {
    if (i.productTrackInventory != true) return null;
    final p = widget.liveProducts.where((p) => p.id == i.productId).firstOrNull;
    if (p == null) return null;
    if (i.variantId != null) {
      return p.variants
          .where((v) => v.id == i.variantId)
          .firstOrNull
          ?.stockQuantity;
    }
    return p.stockQuantity;
  }

  bool get _complete => _groups.values.every((g) => _picked(g) == _need(g));

  List<PromoComponent> _build() {
    final out = <PromoComponent>[];
    for (final i in widget.promo.choiceItems) {
      final n = _counts[i.id] ?? 0;
      if (n <= 0) continue;
      out.add(
        PromoComponent(
          promoId: widget.promo.id,
          productId: i.productId,
          variantId: i.variantId,
          productName: i.productName ?? 'Unknown product',
          variantName: i.variantName,
          quantity: n,
          trackInventory: i.productTrackInventory ?? false,
          sendToKitchen: i.productSendToKitchen ?? true,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.promo.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in groups.entries) ...[
                      _header(entry.key, entry.value),
                      for (final i in entry.value) _optionRow(i, entry.value),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed:
                      _complete
                          ? () => Navigator.of(context).pop(_build())
                          : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.divider,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _complete ? 'Add to cart' : 'Complete all choices',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String name, List<PromoItem> items) {
    final need = _need(items);
    final got = _picked(items);
    final done = got == need;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name - pick $need',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '$got/$need',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: done ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(PromoItem i, List<PromoItem> group) {
    final n = _counts[i.id] ?? 0;
    final avail = _available(i);
    final soldOut = avail != null && avail <= 0;
    final canAdd =
        !soldOut &&
        _picked(group) < _need(group) &&
        (avail == null || n < avail);
    final label =
        i.variantName != null
            ? '${i.productName} (${i.variantName})'
            : (i.productName ?? 'Unknown product');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color:
            n > 0
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: n > 0 ? AppColors.primary : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        soldOut
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                  ),
                ),
                if (soldOut)
                  const Text(
                    'Out of stock',
                    style: TextStyle(fontSize: 11, color: AppColors.danger),
                  )
                else if (avail != null)
                  Text(
                    '$avail in stock',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            onPressed:
                n > 0 ? () => setState(() => _counts[i.id] = n - 1) : null,
          ),
          SizedBox(
            width: 22,
            child: Text(
              '$n',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            onPressed:
                canAdd ? () => setState(() => _counts[i.id] = n + 1) : null,
          ),
        ],
      ),
    );
  }
}
