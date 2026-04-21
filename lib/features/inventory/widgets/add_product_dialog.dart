import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../shared/widgets/app_colors.dart';
import '../inventory_service.dart';
import '../../../core/providers/product_provider.dart';

class AddProductDialog extends ConsumerStatefulWidget {
  const AddProductDialog({super.key});

  @override
  ConsumerState<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends ConsumerState<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController        = TextEditingController();
  final _priceController       = TextEditingController();
  final _descController        = TextEditingController();
  final _barcodeController     = TextEditingController();
  final _skuController         = TextEditingController();
  final _stockController       = TextEditingController(text: '0');
  final _imageUrlController    = TextEditingController();
  final _newCategoryController = TextEditingController();

  // State
  String? _selectedCategoryId;
  bool _trackInventory = false;
  bool _saving = false;
  bool _addingNewCategory = false;

  // Categories loaded from DB
  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true;
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _stockController.dispose();
    _imageUrlController.dispose();
    _newCategoryController.dispose();
    super.dispose();
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

    setState(() => _saving = true);

    try {
      final client = ref.read(supabaseClientProvider);

      await client
          .from('products')
          .insert({
            'business_id':     profile!.businessId,
            'category_id':     _selectedCategoryId,
            'name':            _nameController.text.trim(),
            'description':     _descController.text.trim().isEmpty
                                   ? null
                                   : _descController.text.trim(),
            'price':           double.parse(_priceController.text),
            'image_url':       _imageUrlController.text.trim().isEmpty
                                   ? null
                                   : _imageUrlController.text.trim(),
            'barcode':         _barcodeController.text.trim().isEmpty
                                   ? null
                                   : _barcodeController.text.trim(),
            'sku':             _skuController.text.trim().isEmpty
                                   ? null
                                   : _skuController.text.trim(),
            'track_inventory': _trackInventory,
            'stock_quantity':  _trackInventory
                                   ? (int.tryParse(_stockController.text) ?? 0)
                                   : 0,
            'is_available':    true,
            'is_active':       true,
          });

      // Refresh inventory screen list
      await ref.read(inventoryProvider.notifier).refresh();

      // Invalidate POS product list so it re-fetches on next view.
      // productListProvider is a FutureProvider — it caches its result until
      // explicitly invalidated. Without this, the POS grid never sees the
      // new product even though it's already in the database.
      ref.invalidate(productListProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed to save product: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                  const Icon(Icons.add_box_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text('Add Product',
                      style: TextStyle(
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
                        _label('Initial Stock Quantity'),
                        _field(
                          controller: _stockController,
                          hint: '0',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            if (int.tryParse(v) == null) {
                              return 'Enter a whole number';
                            }
                            return null;
                          },
                        ),
                      ],

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
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Text('Save Product',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
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