// features/inventory/widgets/inventory_shared.dart
// Layout enum + shared micro-widgets used across inventory files.

import 'package:flutter/material.dart';
import '../../../shared/widgets/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

enum InventoryLayout { phone, tablet, desktop }

InventoryLayout inventoryLayoutOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return InventoryLayout.phone;
  if (w < 1024) return InventoryLayout.tablet;
  return InventoryLayout.desktop;
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER / SORT STATE
// ─────────────────────────────────────────────────────────────────────────────

enum StockFilter { all, low, ok, out }

enum SortOrder { nameAsc, nameDesc, priceAsc, priceDesc, stockAsc, stockDesc }

const _sentinel = Object();

class InventoryFilterState {
  final String search;
  final String? category;
  final StockFilter stockFilter;
  final double? minPrice;
  final double? maxPrice;
  final SortOrder sort;

  const InventoryFilterState({
    this.search = '',
    this.category,
    this.stockFilter = StockFilter.all,
    this.minPrice,
    this.maxPrice,
    this.sort = SortOrder.nameAsc,
  });

  bool get hasActiveFilters =>
      category != null ||
      stockFilter != StockFilter.all ||
      minPrice != null ||
      maxPrice != null ||
      sort != SortOrder.nameAsc;

  InventoryFilterState copyWith({
    String? search,
    Object? category = _sentinel,
    StockFilter? stockFilter,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    SortOrder? sort,
  }) =>
      InventoryFilterState(
        search: search ?? this.search,
        category: category == _sentinel ? this.category : category as String?,
        stockFilter: stockFilter ?? this.stockFilter,
        minPrice: minPrice == _sentinel ? this.minPrice : minPrice as double?,
        maxPrice: maxPrice == _sentinel ? this.maxPrice : maxPrice as double?,
        sort: sort ?? this.sort,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED MICRO-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const StatPill(
      {super.key,
      required this.label,
      required this.value,
      required this.color});

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
                  fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
        ],
      ),
    );
  }
}

class InventoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  const InventoryFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.withOpacity(0.5) : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13,
                  color: selected ? c : AppColors.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const RemovableChip(
      {super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 14, color: AppColors.primary.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}

class FilterSectionLabel extends StatelessWidget {
  final String label;
  const FilterSectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.6),
    );
  }
}

class StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool positive;

  const StepperButton(
      {super.key,
      required this.icon,
      required this.onTap,
      this.positive = false});

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

class PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const PriceField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: AppColors.textSecondary.withOpacity(0.5), fontSize: 12),
        prefixText: '₱ ',
        prefixStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        isDense: true,
      ),
    );
  }
}