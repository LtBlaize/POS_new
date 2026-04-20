// lib/features/pos/widgets/category_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/product_provider.dart';
import '../../../shared/widgets/app_colors.dart';

// Category → icon mapping (extend as needed)
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

class CategoryBar extends ConsumerWidget {
  const CategoryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryListProvider);
    final selected = ref.watch(selectedCategoryProvider);

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
          // "All" chip
          _CategoryChip(
            label: 'All',
            icon: Icons.apps_rounded,
            isSelected: selected == null,
            onTap: () =>
                ref.read(selectedCategoryProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),
          ...categories.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CategoryChip(
                  label: cat,
                  icon: _iconFor(cat),
                  isSelected: selected == cat,
                  onTap: () =>
                      ref.read(selectedCategoryProvider.notifier).state = cat,
                ),
              )),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: GestureDetector(
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
                      color: AppColors.primary.withOpacity(0.25),
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
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color:
                      isSelected ? Colors.white : AppColors.textSecondary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}