// lib/features/pos/widgets/product/product_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/product.dart';
import '../../../../core/providers/cart_provider.dart';
import '../../../../core/providers/product_provider.dart';
import '../../../../shared/widgets/app_colors.dart';
import '../../dialogs/variant_picker_dialog.dart';

const _tilePalette = <Color>[
  Color(0xFF0C8599), // teal
  Color(0xFF7048E8), // violet
  Color(0xFF2F9E44), // green
  Color(0xFFC2255C), // raspberry
  Color(0xFF495057), // slate
  Color(0xFF8D5524), // brown
];

/// Stable color per category (or per product name when there's no category).
Color _tileColorFor(String key) {
  final k = key.trim().toLowerCase();
  if (k.isEmpty) return AppColors.textSecondary;
  var h = 0;
  for (final c in k.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _tilePalette[h % _tilePalette.length];
}

IconData _tileIconFor(String category) =>
    switch (category.trim().toLowerCase()) {
      'food' || 'meal' || 'burger' => Icons.lunch_dining_rounded,
      'drinks' || 'drink' || 'beverage' => Icons.local_drink_rounded,
      'dessert' || 'desserts' || 'candy' => Icons.icecream_rounded,
      'snack' || 'snacks' => Icons.cookie_rounded,
      'apparel' => Icons.checkroom_rounded,
      'stationery' => Icons.edit_rounded,
      'electronics' => Icons.devices_rounded,
      _ => Icons.sell_rounded,
    };

class ProductCard extends ConsumerStatefulWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  bool _added = false;

  Product _liveProduct(WidgetRef ref) {
    final products = ref.watch(productListProvider).asData?.value ?? [];
    return products.firstWhere(
      (p) => p.id == widget.product.id,
      orElse: () => widget.product,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() async {
    HapticFeedback.lightImpact();
    await _controller.forward();
    await _controller.reverse();

    final liveProduct = _liveProduct(ref);

    // Products with variants must open the picker instead of adding the
    // base product directly — stock/price are resolved per-variant there.
    if (liveProduct.hasVariants) {
      if (!mounted) return;
      final variant = await VariantPickerDialog.show(context, liveProduct);
      if (variant == null || !mounted) return; // cancelled

      ref.read(cartProvider.notifier).addProduct(liveProduct, variant: variant);

      setState(() => _added = true);
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _added = false);
      return;
    }

    if (liveProduct.trackInventory && liveProduct.stockQuantity <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${liveProduct.name} is out of stock.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    ref.read(cartProvider.notifier).addProduct(liveProduct);

    setState(() => _added = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _added = false);
  }

  @override
  Widget build(BuildContext context) {
    final liveProduct = _liveProduct(ref);
    final cartItems = ref.watch(cartProvider);
    final inCart = cartItems
        .where((i) => i.product.id == widget.product.id)
        .fold(0, (sum, i) => sum + i.quantity);
    final accent = _tileColorFor(
      liveProduct.category.isEmpty ? liveProduct.name : liveProduct.category,
    );

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  inCart > 0
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColors.divider,
              width: inCart > 0 ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon band ────────────────
              SizedBox(
                height: 75,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13),
                        ),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child:
                              _added
                                  ? Icon(
                                    Icons.check_rounded,
                                    color: accent,
                                    size: 32,
                                    key: const ValueKey('check'),
                                  )
                                  : Icon(
                                    _tileIconFor(liveProduct.category),
                                    key: const ValueKey('icon'),
                                    size: 30,
                                    color: accent.withValues(alpha: 0.75),
                                  ),
                        ),
                      ),
                    ),
                    if (inCart > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            '×$inCart',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Info section (fills remaining space) ───────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // When available height is very tight (< 36px),
                      // skip the name and show only the price row.
                      final showName = constraints.maxHeight >= 36;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          if (showName)
                            Flexible(
                              child: Text(
                                liveProduct.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  height: 1.3,
                                ),
                              ),
                            ),

                          // Price + add button — always visible
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '₱${liveProduct.price.toStringAsFixed(0)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 13,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
