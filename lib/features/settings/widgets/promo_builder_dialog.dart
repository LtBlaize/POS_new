// lib/features/settings/widgets/promo_builder_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/models/promo.dart';
import '../../../core/providers/app_context_provider.dart';
import '../../../core/providers/product_provider.dart';
import '../../../core/providers/promo_provider.dart';
import '../../../shared/widgets/app_colors.dart';

class PromoBuilderDialog extends ConsumerStatefulWidget {
  final Promo? existing;
  const PromoBuilderDialog({super.key, this.existing});

  @override
  ConsumerState<PromoBuilderDialog> createState() =>
      _PromoBuilderDialogState();
}

// Local UI draft — never persisted directly; converted to PromoItem on save.
class _PromoItemDraft {
  final String draftId;
  final String productId;
  final String? variantId;
  final String productName;
  final String? variantName;
  final double unitPrice;
  final bool trackInventory;
  final bool sendToKitchen;
  int quantity;

  _PromoItemDraft({
    required this.draftId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    required this.unitPrice,
    required this.trackInventory,
    required this.sendToKitchen,
    this.quantity = 1,
  });
}

class _PromoBuilderDialogState extends ConsumerState<PromoBuilderDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _bundlePriceController = TextEditingController();
  final _buyQtyController = TextEditingController(text: '2');
  final _getQtyController = TextEditingController(text: '1');
  final _getDiscountController = TextEditingController(text: '100');

  PromoType _type = PromoType.bundle;
  bool _isActive = true;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  final List<_PromoItemDraft> _bundleItems = [];
  final List<_PromoItemDraft> _buyItems = [];
  final List<_PromoItemDraft> _getItems = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _nameController.text = p.name;
      _descController.text = p.description ?? '';
      _type = p.promoType;
      _isActive = p.isActive;
      _startDate = p.startDate;
      _endDate = p.endDate;
      _bundlePriceController.text =
          p.bundlePrice != null ? p.bundlePrice!.toStringAsFixed(2) : '';
      _buyQtyController.text = '${p.buyQuantity ?? 1}';
      _getQtyController.text = '${p.getQuantity ?? 1}';
      _getDiscountController.text = '${p.getDiscountPercent ?? 100}';

      for (final i in p.items) {
        final draft = _PromoItemDraft(
          draftId: const Uuid().v4(),
          productId: i.productId,
          variantId: i.variantId,
          productName: i.productName ?? 'Unknown product',
          variantName: i.variantName,
          unitPrice: i.productPrice ?? 0,
          trackInventory: i.productTrackInventory ?? false,
          sendToKitchen: i.productSendToKitchen ?? true,
          quantity: i.quantity,
        );
        switch (i.role) {
          case PromoItemRole.bundle:
            _bundleItems.add(draft);
          case PromoItemRole.buy:
            _buyItems.add(draft);
          case PromoItemRole.get:
            _getItems.add(draft);
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _bundlePriceController.dispose();
    _buyQtyController.dispose();
    _getQtyController.dispose();
    _getDiscountController.dispose();
    super.dispose();
  }

  double get _bundleOriginalTotal =>
      _bundleItems.fold(0, (s, i) => s + i.unitPrice * i.quantity);

  Future<void> _pickProduct(List<_PromoItemDraft> target) async {
    final result = await showModalBottomSheet<_PromoItemDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProductPickerSheet(),
    );
    if (result != null) {
      setState(() => target.add(result));
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Promo name is required.');
      return;
    }

    if (_type == PromoType.bundle) {
      if (_bundleItems.isEmpty) {
        _showError('Add at least one product to the package.');
        return;
      }
      final price = double.tryParse(_bundlePriceController.text);
      if (price == null || price <= 0) {
        _showError('Enter a valid package price.');
        return;
      }
    } else {
      if (_buyItems.isEmpty || _getItems.isEmpty) {
        _showError('Add at least one "buy" product and one "get" product.');
        return;
      }
      final buyQty = int.tryParse(_buyQtyController.text);
      final getQty = int.tryParse(_getQtyController.text);
      if (buyQty == null || buyQty <= 0 || getQty == null || getQty <= 0) {
        _showError('Buy and get quantities must be greater than zero.');
        return;
      }
    }

    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _showError('End date cannot be before start date.');
      return;
    }

    setState(() => _saving = true);

    try {
      final businessId = ref.read(activeBusinessIdProvider);
      if (businessId == null) {
        _showError('No business profile found.');
        setState(() => _saving = false);
        return;
      }

      final items = <PromoItem>[];
      void addAll(List<_PromoItemDraft> drafts, PromoItemRole role) {
        for (final d in drafts) {
          items.add(PromoItem(
            id: const Uuid().v4(), // placeholder — repository re-keys promo_id/id on write
            promoId: widget.existing?.id ?? '',
            productId: d.productId,
            variantId: d.variantId,
            quantity: d.quantity,
            role: role,
            productName: d.productName,
            variantName: d.variantName,
            productPrice: d.unitPrice,
            productTrackInventory: d.trackInventory,
            productSendToKitchen: d.sendToKitchen,
          ));
        }
      }

      if (_type == PromoType.bundle) {
        addAll(_bundleItems, PromoItemRole.bundle);
      } else {
        addAll(_buyItems, PromoItemRole.buy);
        addAll(_getItems, PromoItemRole.get);
      }

      final promo = Promo(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        name: name,
        description:
            _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        promoType: _type,
        bundlePrice: _type == PromoType.bundle
            ? double.tryParse(_bundlePriceController.text)
            : null,
        buyQuantity:
            _type == PromoType.buyXGetY ? int.tryParse(_buyQtyController.text) : null,
        getQuantity:
            _type == PromoType.buyXGetY ? int.tryParse(_getQtyController.text) : null,
        getDiscountPercent: _type == PromoType.buyXGetY
            ? double.tryParse(_getDiscountController.text) ?? 100
            : null,
        isActive: _isActive,
        startDate: _startDate,
        endDate: _endDate,
        items: items,
      );

      final repo = ref.read(promoRepositoryProvider);
      if (_isEdit) {
        await repo.update(promo);
      } else {
        await repo.create(promo);
      }
      ref.invalidate(promoListProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed to save promo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
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
                  Icon(
                      _isEdit
                          ? Icons.edit_outlined
                          : Icons.local_offer_outlined,
                      color: Colors.white,
                      size: 20),
                  const SizedBox(width: 10),
                  Text(_isEdit ? 'Edit Promo' : 'New Promo',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Promo Name *'),
                    _textField(_nameController,
                        hint: 'e.g. Family Meal Package'),
                    const SizedBox(height: 14),

                    _label('Description'),
                    _textField(_descController,
                        hint: 'Optional — shown to cashiers', maxLines: 2),
                    const SizedBox(height: 16),

                    _label('Active'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      title: const Text('Available for sale',
                          style: TextStyle(fontSize: 13)),
                      activeThumbColor: AppColors.primary,
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: _DatePickerField(
                            label: 'Start date (optional)',
                            value: _startDate,
                            onChanged: (d) => setState(() => _startDate = d),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DatePickerField(
                            label: 'End date (optional)',
                            value: _endDate,
                            onChanged: (d) => setState(() => _endDate = d),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _label('Promo Type'),
                    Row(
                      children: [
                        Expanded(
                          child: _TypeCard(
                            title: 'Bundle / Package',
                            subtitle: 'Sell items together for one price',
                            icon: Icons.card_giftcard_rounded,
                            selected: _type == PromoType.bundle,
                            onTap: () =>
                                setState(() => _type = PromoType.bundle),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TypeCard(
                            title: 'Buy X Get Y',
                            subtitle: 'e.g. Buy 2, get 1 free',
                            icon: Icons.local_offer_rounded,
                            selected: _type == PromoType.buyXGetY,
                            onTap: () =>
                                setState(() => _type = PromoType.buyXGetY),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_type == PromoType.bundle)
                      _buildBundleSection()
                    else
                      _buildBuyGetSection(),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.divider,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_isEdit ? 'Update Promo' : 'Save Promo',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBundleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Products in this package'),
        _ItemList(
          items: _bundleItems,
          onRemove: (d) => setState(() => _bundleItems.remove(d)),
          onQuantityChanged: (d, q) => setState(() => d.quantity = q),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _pickProduct(_bundleItems),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Product'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 16),
        _label('Package Price (\u20b1) *'),
        _textField(_bundlePriceController,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        if (_bundleItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PricePreview(
            original: _bundleOriginalTotal,
            promoPrice: double.tryParse(_bundlePriceController.text) ?? 0,
          ),
        ],
      ],
    );
  }

  Widget _buildBuyGetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Buy these products'),
        _ItemList(
          items: _buyItems,
          onRemove: (d) => setState(() => _buyItems.remove(d)),
          onQuantityChanged: (d, q) => setState(() => d.quantity = q),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickProduct(_buyItems),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Product'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),
        _label('Buy quantity *'),
        _textField(_buyQtyController,
            hint: '2', keyboardType: TextInputType.number),
        const SizedBox(height: 20),

        _label('Get these products'),
        _ItemList(
          items: _getItems,
          onRemove: (d) => setState(() => _getItems.remove(d)),
          onQuantityChanged: (d, q) => setState(() => d.quantity = q),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickProduct(_getItems),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Product'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Get quantity *'),
                  _textField(_getQtyController,
                      hint: '1', keyboardType: TextInputType.number),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Discount on "get" item (%)'),
                  _textField(_getDiscountController,
                      hint: '100 = free', keyboardType: TextInputType.number),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Widget _textField(TextEditingController controller,
      {String? hint, TextInputType? keyboardType, int maxLines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}), // keeps the price preview live
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: AppColors.surface,
      ),
    );
  }
}

// ── Type selector card ──────────────────────────────────────────────────────

class _TypeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Date picker field ─────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DatePickerField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null
                        ? 'Not set'
                        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (value != null)
                  GestureDetector(
                    onTap: () => onChanged(null),
                    child: const Icon(Icons.close,
                        size: 14, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Selected-items list ───────────────────────────────────────────────────────

class _ItemList extends StatelessWidget {
  final List<_PromoItemDraft> items;
  final void Function(_PromoItemDraft) onRemove;
  final void Function(_PromoItemDraft, int) onQuantityChanged;

  const _ItemList(
      {required this.items,
      required this.onRemove,
      required this.onQuantityChanged});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Text('No products added yet.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    return Column(
      children: items
          .map((d) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              d.variantName != null
                                  ? '${d.productName} (${d.variantName})'
                                  : d.productName,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                              '\u20b1${d.unitPrice.toStringAsFixed(2)} each${d.trackInventory ? '' : ' \u00b7 not stock-tracked'}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: d.quantity > 1
                          ? () => onQuantityChanged(d, d.quantity - 1)
                          : null,
                    ),
                    Text('${d.quantity}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      onPressed: () => onQuantityChanged(d, d.quantity + 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      onPressed: () => onRemove(d),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ── Price preview (bundle only) ───────────────────────────────────────────────

class _PricePreview extends StatelessWidget {
  final double original;
  final double promoPrice;

  const _PricePreview({required this.original, required this.promoPrice});

  @override
  Widget build(BuildContext context) {
    final savings = (original - promoPrice).clamp(0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Regular price', '\u20b1${original.toStringAsFixed(2)}'),
          _row('Package price', '\u20b1${promoPrice.toStringAsFixed(2)}'),
          const Divider(height: 14),
          _row('Customer saves', '\u20b1${savings.toStringAsFixed(2)}',
              bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: bold ? AppColors.primary : AppColors.textPrimary)),
          ],
        ),
      );
}

// ── Product picker bottom sheet ───────────────────────────────────────────────

class _ProductPickerSheet extends ConsumerStatefulWidget {
  const _ProductPickerSheet();

  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                ),
              ),
              Expanded(
                child: productsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (products) {
                    final query = _searchController.text.trim().toLowerCase();
                    final filtered = query.isEmpty
                        ? products
                        : products
                            .where((p) => p.name.toLowerCase().contains(query))
                            .toList();
                    if (filtered.isEmpty) {
                      return const Center(
                          child: Text('No products found',
                              style: TextStyle(color: AppColors.textSecondary)));
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        if (p.variants.isEmpty) {
                          return _productRow(p, null);
                        }
                        return ExpansionTile(
                          title: Text(p.name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '\u20b1${p.price.toStringAsFixed(2)} \u00b7 ${p.variants.length} variant(s)',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary)),
                          children:
                              p.variants.map((v) => _productRow(p, v)).toList(),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _productRow(Product p, ProductVariant? variant) {
    final variantName = variant?.name;
    final price = p.price + (variant?.priceDelta ?? 0);
    final stock = variant?.stockQuantity ?? p.stockQuantity;

    return ListTile(
      dense: true,
      title: Text(variantName != null ? '${p.name} \u2014 $variantName' : p.name,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        p.trackInventory
            ? '\u20b1${price.toStringAsFixed(2)} \u00b7 $stock in stock'
            : '\u20b1${price.toStringAsFixed(2)} \u00b7 not stock-tracked',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      onTap: () {
        Navigator.pop(
          context,
          _PromoItemDraft(
            draftId: const Uuid().v4(),
            productId: p.id,
            variantId: variant?.id,
            productName: p.name,
            variantName: variantName,
            unitPrice: price,
            trackInventory: p.trackInventory,
            sendToKitchen: p.sendToKitchen,
          ),
        );
      },
    );
  }
}