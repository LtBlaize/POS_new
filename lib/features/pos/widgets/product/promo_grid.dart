// lib/features/pos/widgets/product/promo_grid.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/product.dart';
import '../../../../core/models/promo.dart';
import '../../../../core/providers/cart_provider.dart';
import '../../../../core/providers/product_provider.dart';
import '../../../../core/providers/promo_provider.dart';
import '../../../../shared/widgets/app_colors.dart';

const _kPromoColor = Color(0xFFE67700);

class PromoGrid extends ConsumerWidget {
  const PromoGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allPromos = ref.watch(purchasablePromosProvider);
    final query = ref.watch(posSearchQueryProvider).trim().toLowerCase();

    final promos =
        query.isEmpty
            ? allPromos
            : allPromos.where((p) {
              if (p.name.toLowerCase().contains(query)) return true;
              if ((p.description ?? '').toLowerCase().contains(query)) {
                return true;
              }
              // Also match the products inside the promo, so "burger"
              // finds "Burger Combo" and any promo containing a burger.
              return p.items.any(
                (i) =>
                    (i.productName ?? '').toLowerCase().contains(query) ||
                    (i.variantName ?? '').toLowerCase().contains(query),
              );
            }).toList();

    if (promos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer_outlined,
              size: 40,
              color: AppColors.textSecondary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 10),
            Text(
              query.isEmpty
                  ? 'No promos available right now'
                  : 'No promos match "$query"',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 150,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: promos.length,
      itemBuilder: (context, i) => _PromoCard(promo: promos[i]),
    );
  }
}

/// Horizontal promo row shown above the product grid.
/// Visible on "All", and on any category while a search is active.
class PromoStrip extends ConsumerWidget {
  const PromoStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(selectedCategoryProvider);
    final query = ref.watch(posSearchQueryProvider).trim().toLowerCase();

    // On a specific category with no search, keep the grid clean.
    if (category != null && query.isEmpty) return const SizedBox.shrink();

    final all = ref.watch(purchasablePromosProvider);
    final promos =
        query.isEmpty
            ? all
            : all.where((p) {
              if (p.name.toLowerCase().contains(query)) return true;
              if ((p.description ?? '').toLowerCase().contains(query)) {
                return true;
              }
              return p.items.any(
                (i) =>
                    (i.productName ?? '').toLowerCase().contains(query) ||
                    (i.variantName ?? '').toLowerCase().contains(query),
              );
            }).toList();

    if (promos.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 166,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: promos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder:
            (_, i) => SizedBox(width: 190, child: _PromoCard(promo: promos[i])),
      ),
    );
  }
}

class _PromoCard extends ConsumerWidget {
  final Promo promo;
  const _PromoCard({required this.promo});

  // Bakes buy/get multipliers into each component's quantity so it means
  // "per one unit of the promo in the cart" — matching PromoComponent's
  // documented contract and checkPromoStock's own neededPerUnit math.
  List<PromoComponent> _buildComponents() {
    final components = <PromoComponent>[];
    void addFrom(List<PromoItem> items, int multiplier) {
      for (final i in items) {
        components.add(
          PromoComponent(
            promoId: promo.id,
            productId: i.productId,
            variantId: i.variantId,
            productName: i.productName ?? 'Unknown product',
            variantName: i.variantName,
            quantity: i.quantity * multiplier,
            trackInventory: i.productTrackInventory ?? false,
            sendToKitchen: i.productSendToKitchen ?? true,
          ),
        );
      }
    }

    if (promo.promoType == PromoType.bundle) {
      addFrom(promo.bundleItems, 1);
    } else {
      addFrom(promo.buyItems, promo.buyQuantity ?? 1);
      addFrom(promo.getItems, promo.getQuantity ?? 1);
    }
    return components;
  }

  /// Live stock check against the cached product list — same source and
  /// same "cache, not a live round-trip" tradeoff as the barcode-scan
  /// add-to-cart path in pos_screen.dart. Final authority is still
  /// CheckoutService at checkout time.
  String? _checkLiveStock(
    List<Product> liveProducts,
    List<PromoComponent> components,
  ) {
    for (final c in components) {
      if (!c.trackInventory) continue;
      final product =
          liveProducts.where((p) => p.id == c.productId).firstOrNull;
      if (product == null) continue;
      final available =
          c.variantId != null
              ? product.variants
                  .where((v) => v.id == c.variantId)
                  .firstOrNull
                  ?.stockQuantity
              : product.stockQuantity;
      if (available != null && c.quantity > available) {
        final label =
            c.variantName != null
                ? '${c.productName} (${c.variantName})'
                : c.productName;
        return '$label only has $available in stock (this needs ${c.quantity}).';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBundle = promo.promoType == PromoType.bundle;
    final itemCount = promo.items.length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _handleTap(context, ref),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
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
              Container(
                height: 48,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _kPromoColor.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBundle
                          ? Icons.card_giftcard_rounded
                          : Icons.local_offer_rounded,
                      size: 22,
                      color: _kPromoColor.withValues(alpha: 0.85),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kPromoColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PROMO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isBundle
                            ? '$itemCount item${itemCount == 1 ? '' : 's'}'
                            : 'Buy ${promo.buyQuantity ?? 1} Get ${promo.getQuantity ?? 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\u20b1${promo.effectivePrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (promo.savings > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Save \u20b1${promo.savings.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    final components = _buildComponents();
    final liveProducts = ref.read(productListProvider).asData?.value ?? [];
    final error = _checkLiveStock(liveProducts, components);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    ref.read(cartProvider.notifier).addPromo(promo, components);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${promo.name} added to cart'),
        backgroundColor: AppColors.success,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }
}
