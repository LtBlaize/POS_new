// features/inventory/widgets/inventory_filter.dart
// Filter button + bottom sheet, sort button, active filter chips row.

import 'package:flutter/material.dart';
import '../inventory_service.dart';
import '../../../shared/widgets/app_colors.dart';
import 'inventory_shared.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class FilterButton extends StatelessWidget {
  final InventoryFilterState filter;
  final List<String> categories;
  final List<InventoryEntry> entries;
  final ValueChanged<InventoryFilterState> onChanged;

  const FilterButton({
    super.key,
    required this.filter,
    required this.categories,
    required this.entries,
    required this.onChanged,
  });

  bool get _hasFilter =>
      filter.category != null ||
      filter.stockFilter != StockFilter.all ||
      filter.minPrice != null ||
      filter.maxPrice != null;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: _hasFilter,
      backgroundColor: AppColors.primary,
      child: IconButton(
        onPressed: () => _showSheet(context),
        icon: Icon(
          Icons.tune_rounded,
          size: 18,
          color: _hasFilter ? AppColors.primary : AppColors.textSecondary,
        ),
        tooltip: 'Filters',
        style: IconButton.styleFrom(
          backgroundColor: _hasFilter
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FilterSheet(
        filter: filter,
        categories: categories,
        entries: entries,
        onChanged: onChanged,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class FilterSheet extends StatefulWidget {
  final InventoryFilterState filter;
  final List<String> categories;
  final List<InventoryEntry> entries;
  final ValueChanged<InventoryFilterState> onChanged;

  const FilterSheet({
    super.key,
    required this.filter,
    required this.categories,
    required this.entries,
    required this.onChanged,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late InventoryFilterState _local;
  late RangeValues _priceRange;
  late double _priceMin;
  late double _priceMax;

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _local = widget.filter;

    final prices = widget.entries.map((e) => e.product.price).toList();
    _priceMin = prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b);
    _priceMax =
        prices.isEmpty ? 9999 : prices.reduce((a, b) => a > b ? a : b);
    if (_priceMax == _priceMin) _priceMax = _priceMin + 100;

    _priceRange = RangeValues(
      _local.minPrice ?? _priceMin,
      _local.maxPrice ?? _priceMax,
    );
    _minCtrl.text =
        _local.minPrice != null ? _local.minPrice!.toStringAsFixed(0) : '';
    _maxCtrl.text =
        _local.maxPrice != null ? _local.maxPrice!.toStringAsFixed(0) : '';
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    widget.onChanged(_local);
    Navigator.pop(context);
  }

  void _reset() {
    setState(() {
      _local = _local.copyWith(
        category: null,
        stockFilter: StockFilter.all,
        minPrice: null,
        maxPrice: null,
      );
      _priceRange = RangeValues(_priceMin, _priceMax);
      _minCtrl.clear();
      _maxCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _local.category != null ||
        _local.stockFilter != StockFilter.all ||
        _local.minPrice != null ||
        _local.maxPrice != null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  const Text('Filters',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (hasChanges)
                    TextButton(
                      onPressed: _reset,
                      child: const Text('Reset all',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  // ── Category ────────────────────────────────────
                  const FilterSectionLabel(label: 'Category'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InventoryFilterChip(
                        label: 'All',
                        selected: _local.category == null,
                        onTap: () => setState(
                            () => _local = _local.copyWith(category: null)),
                      ),
                      ...widget.categories.map((cat) => InventoryFilterChip(
                            label: cat,
                            selected: _local.category == cat,
                            onTap: () => setState(() =>
                                _local = _local.copyWith(category: cat)),
                          )),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // ── Stock status ────────────────────────────────
                  const FilterSectionLabel(label: 'Stock Status'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InventoryFilterChip(
                        label: 'All',
                        selected: _local.stockFilter == StockFilter.all,
                        onTap: () => setState(() => _local =
                            _local.copyWith(stockFilter: StockFilter.all)),
                      ),
                      InventoryFilterChip(
                        label: 'OK',
                        icon: Icons.check_circle_outline_rounded,
                        color: const Color(0xFF10B981),
                        selected: _local.stockFilter == StockFilter.ok,
                        onTap: () => setState(() => _local =
                            _local.copyWith(stockFilter: StockFilter.ok)),
                      ),
                      InventoryFilterChip(
                        label: 'Low',
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFF59E0B),
                        selected: _local.stockFilter == StockFilter.low,
                        onTap: () => setState(() => _local =
                            _local.copyWith(stockFilter: StockFilter.low)),
                      ),
                      InventoryFilterChip(
                        label: 'Out of Stock',
                        icon: Icons.remove_circle_outline_rounded,
                        color: AppColors.danger,
                        selected: _local.stockFilter == StockFilter.out,
                        onTap: () => setState(() => _local =
                            _local.copyWith(stockFilter: StockFilter.out)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // ── Price range ─────────────────────────────────
                  const FilterSectionLabel(label: 'Price Range'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '₱${_priceRange.start.toStringAsFixed(0)} – ₱${_priceRange.end.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                      const Spacer(),
                      if (_local.minPrice != null || _local.maxPrice != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _local = _local.copyWith(
                                minPrice: null, maxPrice: null);
                            _priceRange =
                                RangeValues(_priceMin, _priceMax);
                            _minCtrl.clear();
                            _maxCtrl.clear();
                          }),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap),
                          child: const Text('Clear',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.danger)),
                        ),
                    ],
                  ),
                  RangeSlider(
                    values: _priceRange,
                    min: _priceMin,
                    max: _priceMax,
                    divisions: ((_priceMax - _priceMin) / 10)
                        .round()
                        .clamp(1, 200),
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() {
                        _priceRange = v;
                        _local = _local.copyWith(
                          minPrice: v.start > _priceMin ? v.start : null,
                          maxPrice: v.end < _priceMax ? v.end : null,
                        );
                        _minCtrl.text = v.start > _priceMin
                            ? v.start.toStringAsFixed(0)
                            : '';
                        _maxCtrl.text = v.end < _priceMax
                            ? v.end.toStringAsFixed(0)
                            : '';
                      });
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: PriceField(
                          controller: _minCtrl,
                          hint: 'Min (₱${_priceMin.toStringAsFixed(0)})',
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            setState(() {
                              _local = _local.copyWith(minPrice: d);
                              _priceRange = RangeValues(
                                d?.clamp(_priceMin, _priceMax) ?? _priceMin,
                                _priceRange.end,
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PriceField(
                          controller: _maxCtrl,
                          hint: 'Max (₱${_priceMax.toStringAsFixed(0)})',
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            setState(() {
                              _local = _local.copyWith(maxPrice: d);
                              _priceRange = RangeValues(
                                _priceRange.start,
                                d?.clamp(_priceMin, _priceMax) ?? _priceMax,
                              );
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Apply Filters',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SORT BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class SortButton extends StatelessWidget {
  final SortOrder sort;
  final ValueChanged<SortOrder> onChanged;

  const SortButton({super.key, required this.sort, required this.onChanged});

  bool get _isDefault => sort == SortOrder.nameAsc;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortOrder>(
      initialValue: sort,
      onSelected: onChanged,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: 'Sort',
      itemBuilder: (_) => [
        _sortItem(SortOrder.nameAsc, 'Name A → Z',
            Icons.sort_by_alpha_rounded),
        _sortItem(SortOrder.nameDesc, 'Name Z → A',
            Icons.sort_by_alpha_rounded),
        const PopupMenuDivider(),
        _sortItem(SortOrder.priceAsc, 'Price: Low → High',
            Icons.arrow_upward_rounded),
        _sortItem(SortOrder.priceDesc, 'Price: High → Low',
            Icons.arrow_downward_rounded),
        const PopupMenuDivider(),
        _sortItem(SortOrder.stockAsc, 'Stock: Low → High',
            Icons.arrow_upward_rounded),
        _sortItem(SortOrder.stockDesc, 'Stock: High → Low',
            Icons.arrow_downward_rounded),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _isDefault
              ? AppColors.surface
              : AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isDefault
                ? AppColors.divider
                : AppColors.primary.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded,
                size: 16,
                color:
                    _isDefault ? AppColors.textSecondary : AppColors.primary),
            const SizedBox(width: 4),
            Text(
              _sortLabel(sort),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isDefault
                    ? AppColors.textSecondary
                    : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<SortOrder> _sortItem(
          SortOrder value, String label, IconData icon) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13)),
            if (sort == value) ...[
              const Spacer(),
              const Icon(Icons.check_rounded,
                  size: 16, color: AppColors.primary),
            ],
          ],
        ),
      );

  String _sortLabel(SortOrder s) => switch (s) {
        SortOrder.nameAsc => 'Name A→Z',
        SortOrder.nameDesc => 'Name Z→A',
        SortOrder.priceAsc => 'Price ↑',
        SortOrder.priceDesc => 'Price ↓',
        SortOrder.stockAsc => 'Stock ↑',
        SortOrder.stockDesc => 'Stock ↓',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVE FILTER CHIPS ROW
// ─────────────────────────────────────────────────────────────────────────────

class ActiveFilterChips extends StatelessWidget {
  final InventoryFilterState filter;
  final ValueChanged<InventoryFilterState> onChanged;

  const ActiveFilterChips(
      {super.key, required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (filter.category != null) {
      chips.add(RemovableChip(
        label: filter.category!,
        onRemove: () => onChanged(filter.copyWith(category: null)),
      ));
    }

    if (filter.stockFilter != StockFilter.all) {
      final label = switch (filter.stockFilter) {
        StockFilter.low => 'Low stock',
        StockFilter.ok => 'In stock',
        StockFilter.out => 'Out of stock',
        StockFilter.all => '',
      };
      chips.add(RemovableChip(
        label: label,
        onRemove: () =>
            onChanged(filter.copyWith(stockFilter: StockFilter.all)),
      ));
    }

    if (filter.minPrice != null || filter.maxPrice != null) {
      final min = filter.minPrice != null
          ? '₱${filter.minPrice!.toStringAsFixed(0)}'
          : '₱0';
      final max = filter.maxPrice != null
          ? '₱${filter.maxPrice!.toStringAsFixed(0)}'
          : '∞';
      chips.add(RemovableChip(
        label: '$min – $max',
        onRemove: () =>
            onChanged(filter.copyWith(minPrice: null, maxPrice: null)),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }
}