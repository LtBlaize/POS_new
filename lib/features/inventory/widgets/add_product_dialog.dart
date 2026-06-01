import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../shared/widgets/app_colors.dart';
import '../inventory_service.dart';
import '../../../core/providers/product_provider.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/providers/staff_provider.dart';
import '../../../core/models/staff.dart';

class AddProductDialog extends ConsumerStatefulWidget {
final Product? product;
const AddProductDialog({super.key, this.product});

  @override
  ConsumerState<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends ConsumerState<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController        = TextEditingController();
  final _priceController       = TextEditingController();
  final _costController        = TextEditingController();
  final _descController        = TextEditingController();
  final _barcodeController     = TextEditingController();
  final _skuController         = TextEditingController();
  final _stockController       = TextEditingController(text: '0');
  final _imageUrlController    = TextEditingController();
  final _newCategoryController = TextEditingController();

  // State
  String? _selectedCategoryId;
  bool _trackInventory = false;
  bool _sendToKitchen = true;
  bool _saving = false;
  bool _addingNewCategory = false;
  int _originalStock = 0; // ← added: used to block non-owners from reducing stock on edit

  // Categories loaded from DB
  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true;

  // Variants
  List<ProductVariant> _variants = [];
  final List<String> _removedVariantIds = [];
  bool _variantsLoading = false;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();

    // Pre-fill if editing
    final p = widget.product;
    if (p != null) {
      _nameController.text     = p.name;
      _priceController.text    = p.price.toStringAsFixed(2);
      _descController.text     = p.description ?? '';
      _barcodeController.text  = p.barcode ?? '';
      _skuController.text      = p.sku ?? '';
      _costController.text     = p.costPrice > 0 ? p.costPrice.toStringAsFixed(2) : '';
      _stockController.text    = '${p.stockQuantity}';
      _sendToKitchen           = p.sendToKitchen;
      _imageUrlController.text = p.imageUrl ?? '';
      _trackInventory          = p.trackInventory;
      _selectedCategoryId      = p.categoryId;
      _originalStock           = p.stockQuantity;
      // Load existing variants
      _variants = List<ProductVariant>.from(p.variants);
      if (_variants.isEmpty && p.id.isNotEmpty) _loadVariants(p.id);
    }
  }

  Future<void> _loadVariants(String productId) async {
    setState(() => _variantsLoading = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final rows = await client
          .from('product_variants')
          .select()
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('name');
      if (mounted) {
        setState(() {
          _variants = (rows as List)
              .map((r) => ProductVariant.fromMap(r as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[AddProductDialog] variant load failed: $e');
    } finally {
      if (mounted) setState(() => _variantsLoading = false);
    }
  }

  // ── Load categories for this business ──────────────────────────────────────

  Future<void> _loadCategories() async {
    final profile = ref.read(profileProvider).asData?.value;
    if (profile?.businessId == null) return;

    try {
      final client = ref.read(supabaseClientProvider);
      final rows = await client
          .from('categories')
          .select('id, name')
          .eq('business_id', profile!.businessId!)
          .eq('is_active', true)
          .order('name');

      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(rows as List);
          _categoriesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  // ── Create a new category row then select it ───────────────────────────────

  Future<void> _createCategory(String name) async {
    final profile = ref.read(profileProvider).asData?.value;
    if (profile?.businessId == null) return;

    final client = ref.read(supabaseClientProvider);
    final row = await client
        .from('categories')
        .insert({
          'business_id': profile!.businessId,
          'name': name.trim(),
        })
        .select('id, name')
        .single();

    final category = row;

    setState(() {
      _categories.add(category);
      _categories.sort((a, b) =>
          (a['name'] as String).compareTo(b['name'] as String));
      _selectedCategoryId = category['id'] as String;
      _addingNewCategory  = false;
      _newCategoryController.clear();
    });
  }

  // ── Save product ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = ref.read(profileProvider).asData?.value;
    if (profile?.businessId == null) {
      _showError('No business profile found.');
      return;
    }

    // ← added: block non-owners from reducing stock when editing
    if (widget.product != null && _trackInventory) {
      final staff = ref.read(activeStaffProvider);
      final isOwner = staff?.role == StaffRole.owner;
      final newStock = int.tryParse(_stockController.text) ?? 0;
      if (!isOwner && newStock < _originalStock) {
        _showError('Cannot reduce stock below $_originalStock');
        return;
      }
    }

    for (int i = 0; i < _variants.length; i++) {
      if (_variants[i].name.trim().isEmpty) {
        _showError('Variant ${i + 1} is missing a name.');
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final client = ref.read(supabaseClientProvider);
      final data = {
        'category_id':     _selectedCategoryId,
        'name':            _nameController.text.trim(),
        'description':     _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        'price':           double.parse(_priceController.text),
        'image_url':       _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
        'barcode':         _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
        'sku':             _skuController.text.trim().isEmpty ? null : _skuController.text.trim(),
        'cost_price':      double.tryParse(_costController.text) ?? 0,
        'track_inventory': _trackInventory,
        'stock_quantity':  _trackInventory ? (int.tryParse(_stockController.text) ?? 0) : 0,
        'send_to_kitchen': _sendToKitchen,
      };

      String productId;

      if (widget.product == null) {
        // ── Insert — capture returned id ────────────────────────────────
        final row = await client
            .from('products')
            .insert({
              ...data,
              'business_id': profile!.businessId,
              'is_available': true,
              'is_active': true,
            })
            .select('id')
            .single();
        productId = row['id'] as String;
      } else {
        // ── Update ──────────────────────────────────────────────────────
        await client
            .from('products')
            .update(data)
            .eq('id', widget.product!.id);
        productId = widget.product!.id;
      }

      await _saveVariants(client, productId);

      await ref.read(inventoryProvider.notifier).refresh();
      ref.invalidate(productListProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed to save product: $e');
    }
  }

  Future<void> _saveVariants(dynamic client, String productId) async {
    for (final v in _variants) {
      final payload = {
        'product_id': productId,
        'name': v.name,
        'option_type': v.optionType,
        'price_delta': v.priceDelta,
        'sku': v.sku?.trim().isEmpty == true ? null : v.sku,
        'barcode': v.barcode?.trim().isEmpty == true ? null : v.barcode,
        'stock_quantity': v.stockQuantity,
        'cost_price': v.costPrice,
        'is_active': true,
      };
      if (v.id.startsWith('new_')) {
        await client.from('product_variants').insert(payload);
      } else {
        await client
            .from('product_variants')
            .update(payload)
            .eq('id', v.id);
      }
    }
    // Soft-delete removed variants
    for (final id in _removedVariantIds) {
      await client
          .from('product_variants')
          .update({'is_active': false})
          .eq('id', id);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ← added: resolve role once for the whole form
    final staff = ref.read(activeStaffProvider);
    final isOwner = staff?.role == StaffRole.owner;
    final isEdit = widget.product != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(isEdit ? Icons.edit_outlined : Icons.add_box_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(isEdit ? 'Edit Product' : 'Add Product',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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

            // ── Form ───────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      _label('Product Name *'),
                      _field(
                        controller: _nameController,
                        hint: 'e.g. Cheeseburger',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Price
                      _label('Price (₱) *'),
                      _field(
                        controller: _priceController,
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Price is required';
                          }
                          if (double.tryParse(v) == null) {
                            return 'Enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Cost price
                      _label('Cost Price (₱)'),
                      _field(
                        controller: _costController,
                        hint: '0.00  (optional — used for margin reports)',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 14),

                      // Description
                      _label('Description'),
                      _field(
                        controller: _descController,
                        hint: 'Optional product description',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),

                      // Category
                      _label('Category'),
                      if (_categoriesLoading)
                        const SizedBox(
                          height: 44,
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      else if (_addingNewCategory)
                        _NewCategoryField(
                          controller: _newCategoryController,
                          onSave: (name) => _createCategory(name),
                          onCancel: () =>
                              setState(() => _addingNewCategory = false),
                        )
                      else
                        _CategoryDropdown(
                          categories: _categories,
                          selectedId: _selectedCategoryId,
                          onChanged: (id) =>
                              setState(() => _selectedCategoryId = id),
                          onAddNew: () =>
                              setState(() => _addingNewCategory = true),
                        ),
                      const SizedBox(height: 14),

                      // Barcode + SKU (side by side)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Barcode'),
                                _field(
                                  controller: _barcodeController,
                                  hint: 'e.g. 1234567890',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('SKU'),
                                _field(
                                  controller: _skuController,
                                  hint: 'e.g. SKU-001',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Image URL
                      _label('Image URL'),
                      _field(
                        controller: _imageUrlController,
                        hint: 'https://…',
                      ),

                      const SizedBox(height: 10),
                        _SendToKitchenToggle(
                          value: _sendToKitchen,
                          onChanged: (v) => setState(() => _sendToKitchen = v),
                        ),
                      const SizedBox(height: 14),

                      // Track inventory toggle
                      _TrackInventoryToggle(
                        value: _trackInventory,
                        onChanged: (v) =>
                            setState(() => _trackInventory = v),
                      ),
                      
                      
                      // Stock quantity — only visible when tracking
                      if (_trackInventory) ...[
                        const SizedBox(height: 14),
                        // ← changed: label differs for add vs edit
                        _label(isEdit ? 'Stock Quantity' : 'Initial Stock Quantity'),
                        _field(
                          controller: _stockController,
                          hint: '0',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final parsed = int.tryParse(v);
                            if (parsed == null) return 'Enter a whole number';
                            // ← added: inline validator for non-owners on edit
                            if (isEdit && !isOwner && parsed < _originalStock) {
                              return 'Cannot go below $_originalStock';
                            }
                            return null;
                          },
                        ),
                        // ← added: hint shown to non-owners when editing
                        if (isEdit && !isOwner) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Minimum: $_originalStock (cannot reduce stock)',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ],

                      const SizedBox(height: 20),

                      // ── Variants section ───────────────────────────────
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _priceController,
                        builder: (_, _, _) => _VariantsSection(
                        productId: widget.product?.id,
                        basePrice: double.tryParse(_priceController.text) ?? 0,
                        variants: _variants,
                        loading: _variantsLoading,
                        onAdd: (v) => setState(() => _variants.add(v)),
                        onUpdate: (i, v) =>
                            setState(() => _variants[i] = v),
                        onRemove: (i) => setState(() {
                          final removed = _variants[i];
                          if (!removed.id.startsWith('new_')) {
                            _removedVariantIds.add(removed.id);
                          }
                          _variants.removeAt(i);
                        }),
                      ),
                      ), // ValueListenableBuilder

                      const SizedBox(height: 24),

                      // Save button
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
                          child: Text(
                            isEdit ? 'Update Product' : 'Save Product',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Widget _field({
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.5),
              fontSize: 13),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.danger, width: 1)),
          filled: true,
          fillColor: AppColors.surface,
        ),
      );
}

// ── Category dropdown ─────────────────────────────────────────────────────────

class _CategoryDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final String? selectedId;
  final void Function(String? id) onChanged;
  final VoidCallback onAddNew;

  const _CategoryDropdown({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isExpanded: true,
                hint: const Text('Select category',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('No category',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  ...categories.map((c) => DropdownMenuItem<String>(
                        value: c['id'] as String,
                        child: Text(c['name'] as String),
                      )),
                ],
                onChanged: (id) => onChanged(id),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onAddNew,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('New',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}

// ── New category inline field ─────────────────────────────────────────────────

class _NewCategoryField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSave;
  final VoidCallback onCancel;

  const _NewCategoryField({
    required this.controller,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'New category name',
              hintStyle: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.5),
                  fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
              filled: true,
              fillColor: AppColors.surface,
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) onSave(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              onSave(controller.text);
            }
          },
          icon: const Icon(Icons.check_circle,
              color: AppColors.success, size: 24),
          tooltip: 'Save category',
        ),
        IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.cancel_outlined,
              color: AppColors.textSecondary, size: 24),
          tooltip: 'Cancel',
        ),
      ],
    );
  }
}
class _SendToKitchenToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SendToKitchenToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? Colors.orange.withOpacity(0.05)
            : AppColors.surface,
        border: Border.all(
          color: value
              ? Colors.orange.withOpacity(0.3)
              : AppColors.divider,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.kitchen_outlined,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send to Kitchen',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('This item will appear on the kitchen display',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.orange,
          ),
        ],
      ),
    );
  }
}

// ── Track inventory toggle ────────────────────────────────────────────────────

class _TrackInventoryToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TrackInventoryToggle(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.surface,
        border: Border.all(
          color: value
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.divider,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Track Inventory',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('Monitor and deduct stock on each sale',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ── Variants section ──────────────────────────────────────────────────────────

class _VariantsSection extends StatefulWidget {
  final String? productId;
  final double basePrice;
  final List<ProductVariant> variants;
  final bool loading;
  final void Function(ProductVariant) onAdd;
  final void Function(int, ProductVariant) onUpdate;
  final void Function(int) onRemove;

  const _VariantsSection({
    required this.productId,
    required this.basePrice,
    required this.variants,
    required this.loading,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_VariantsSection> createState() => _VariantsSectionState();
}

class _VariantsSectionState extends State<_VariantsSection> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.variants.isNotEmpty;
  }

  void _addVariant() {
    final newVariant = ProductVariant(
      id: 'new_${DateTime.now().millisecondsSinceEpoch}',
      productId: widget.productId ?? '',
      name: '',
      priceDelta: 0,
      stockQuantity: 0,
      costPrice: 0,
    );
    widget.onAdd(newVariant);
    setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.variants.length;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _expanded
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.divider,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // ── Header / toggle ──────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.tune_outlined,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Variants',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text(
                          count == 0
                              ? 'Size, colour, flavour, etc.'
                              : '$count variant${count > 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (widget.loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),

          // ── Expanded body ────────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            if (widget.variants.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Text(
                  'No variants yet. Add one below.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary.withOpacity(0.7)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.variants.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1),
                itemBuilder: (_, i) => _VariantRow(
                  variant: widget.variants[i],
                  basePrice: widget.basePrice,
                  onUpdate: (v) => widget.onUpdate(i, v),
                  onRemove: () => widget.onRemove(i),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addVariant,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add Variant',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Single variant row (inline edit) ─────────────────────────────────────────

class _VariantRow extends StatefulWidget {
  final ProductVariant variant;
  final double basePrice;
  final void Function(ProductVariant) onUpdate;
  final VoidCallback onRemove;

  const _VariantRow({
    required this.variant,
    required this.basePrice,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_VariantRow> createState() => _VariantRowState();
}

class _VariantRowState extends State<_VariantRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _deltaCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _optionTypeCtrl;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final v = widget.variant;
    _nameCtrl  = TextEditingController(text: v.name);
    _deltaCtrl = TextEditingController(
        text: v.priceDelta == 0 ? '' : v.priceDelta.toStringAsFixed(2));
    _stockCtrl = TextEditingController(text: '${v.stockQuantity}');
    _costCtrl  = TextEditingController(
        text: v.costPrice == 0 ? '' : v.costPrice.toStringAsFixed(2));
    _skuCtrl          = TextEditingController(text: v.sku ?? '');
    _barcodeCtrl      = TextEditingController(text: v.barcode ?? '');
    _optionTypeCtrl   = TextEditingController(text: v.optionType ?? '');

    // Auto-expand new (unsaved) rows so user fills them in immediately
    _expanded = v.id.startsWith('new_');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _deltaCtrl.dispose();
    _stockCtrl.dispose();
    _costCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _optionTypeCtrl.dispose();
    super.dispose();
  }

  void _pushUpdate() {
    widget.onUpdate(widget.variant.copyWith(
      name: _nameCtrl.text.trim(),
      optionType: _optionTypeCtrl.text.trim().isEmpty ? null : _optionTypeCtrl.text.trim(),
      priceDelta: double.tryParse(_deltaCtrl.text) ?? 0,
      stockQuantity: int.tryParse(_stockCtrl.text) ?? 0,
      costPrice: double.tryParse(_costCtrl.text) ?? 0,
      sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final resolvedPrice =
        widget.basePrice + (double.tryParse(_deltaCtrl.text) ?? 0);

    return Column(
      children: [
        // ── Collapsed summary row ──────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _nameCtrl.text.isEmpty ? 'New variant' : _nameCtrl.text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _nameCtrl.text.isEmpty
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '₱${resolvedPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Text(
                  'Stock: ${_stockCtrl.text}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: const Icon(Icons.close,
                      size: 16, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ),

        // ── Expanded edit fields ───────────────────────────────────────
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + option type row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _miniField(
                        controller: _nameCtrl,
                        label: 'Variant name *',
                        hint: 'e.g. Large',
                        onChanged: (_) => setState(_pushUpdate),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _miniField(
                        controller: _optionTypeCtrl,
                        label: 'Type',
                        hint: 'size / colour',
                        onChanged: (_) => _pushUpdate(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Price delta + stock + cost
                Row(
                  children: [
                    Expanded(
                      child: _miniField(
                        controller: _deltaCtrl,
                        label: 'Price +/− (₱)',
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        onChanged: (_) => setState(_pushUpdate),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniField(
                        controller: _stockCtrl,
                        label: 'Stock',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _pushUpdate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniField(
                        controller: _costCtrl,
                        label: 'Cost (₱)',
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => _pushUpdate(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // SKU
                Row(
                  children: [
                    Expanded(
                      child: _miniField(
                        controller: _skuCtrl,
                        label: 'SKU',
                        hint: 'Optional',
                        onChanged: (_) => _pushUpdate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniField(
                        controller: _barcodeCtrl,
                        label: 'Barcode',
                        hint: 'Optional',
                        onChanged: (_) => _pushUpdate(),
                      ),
                    ),
                  ],
                ),

                // Resolved price hint
                const SizedBox(height: 6),
                Text(
                  'Final price: ₱${resolvedPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary.withOpacity(0.8),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _miniField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    required void Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.5),
                fontSize: 12),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.divider)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5)),
            filled: true,
            fillColor: AppColors.surface,
            isDense: true,
          ),
        ),
      ],
    );
  }
}