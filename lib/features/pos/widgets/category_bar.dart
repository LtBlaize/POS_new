// lib/features/pos/widgets/category_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/product_provider.dart';
import '../../../core/providers/promo_provider.dart';
import '../../../shared/widgets/app_colors.dart';

const _categoryIcons = <String, IconData>{
  'Food': Icons.lunch_dining_rounded,
  'Drinks': Icons.local_drink_rounded,
  'Apparel': Icons.checkroom_rounded,
  'Stationery': Icons.edit_rounded,
  'Electronics': Icons.devices_rounded,
  'Desserts': Icons.icecream_rounded,
};

IconData _iconFor(String category) =>
    _categoryIcons[category] ?? Icons.label_outline_rounded;

enum PosViewMode { products, promos }

/// Toggled by the "Promos" chip in CategoryBar; read by _POSMain to decide
/// whether to render ProductGrid or PromoGrid. Lives here rather than in
/// pos_screen.dart since CategoryBar is the only thing that writes to it.
final posViewModeProvider = StateProvider<PosViewMode>((ref) => PosViewMode.products);

class CategoryBar extends ConsumerWidget {
  const CategoryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider); // FutureProvider now
    final selected = ref.watch(selectedCategoryProvider);
    final viewMode = ref.watch(posViewModeProvider);
    final hasPromos = ref.watch(purchasablePromosProvider).isNotEmpty;

    // Resolve categories — show empty bar while loading, never block UI
    final categories = categoriesAsync.asData?.value ?? [];

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          _CategoryChip(
            label: 'All',
            icon: Icons.apps_rounded,
            isSelected: viewMode == PosViewMode.products && selected == null,
            onTap: () {
              ref.read(posViewModeProvider.notifier).state = PosViewMode.products;
              ref.read(selectedCategoryProvider.notifier).state = null;
              ref.read(posSearchQueryProvider.notifier).state = '';
            },
          ),
          const SizedBox(width: 8),
          ...categories.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CategoryChip(
                  label: cat,
                  icon: _iconFor(cat),
                  isSelected: viewMode == PosViewMode.products && selected == cat,
                  onTap: () {
                    ref.read(posViewModeProvider.notifier).state = PosViewMode.products;
                    ref.read(selectedCategoryProvider.notifier).state = cat;
                    ref.read(posSearchQueryProvider.notifier).state = '';
                  },
                ),
              )),
          if (hasPromos) ...[
            const SizedBox(width: 8),
            _CategoryChip(
              label: 'Promos',
              icon: Icons.local_offer_rounded,
              isSelected: viewMode == PosViewMode.promos,
              onTap: () =>
                  ref.read(posViewModeProvider.notifier).state = PosViewMode.promos,
            ),
          ],
        ],
      ),
    );
  }
}


class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : AppColors.textSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}