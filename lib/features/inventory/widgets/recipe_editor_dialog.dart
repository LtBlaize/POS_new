// lib/features/inventory/widgets/recipe_editor_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../../core/providers/product_provider.dart';
import '../../../core/providers/recipe_provider.dart';
import '../../../shared/widgets/app_colors.dart';

Future<void> showRecipeEditor(BuildContext context, Product product) {
  return showDialog(
    context: context,
    builder: (_) => _RecipeEditor(product: product),
  );
}

class _Line {
  final String productId;
  final String? variantId;
  final String label;
  int qty;
  _Line(this.productId, this.variantId, this.label, this.qty);
}

class _RecipeEditor extends ConsumerStatefulWidget {
  final Product product;
  const _RecipeEditor({required this.product});

  @override
  ConsumerState<_RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<_RecipeEditor> {
  final List<_Line> _lines = [];
  bool _saving = false;
  bool _wouldLoop(String componentId) {
    final recipes = ref.read(recipesProvider).asData?.value ?? const {};
    final seen = <String>{};
    bool reaches(String id) {
      if (id == widget.product.id) return true;
      if (!seen.add(id)) return false;
      return (recipes[id] ?? const []).any(
        (l) => reaches(l.componentProductId),
      );
    }

    return reaches(componentId);
  }

  @override
  void initState() {
    super.initState();
    final existing =
        ref.read(recipesProvider).asData?.value[widget.product.id] ?? [];
    for (final l in existing) {
      _lines.add(
        _Line(
          l.componentProductId,
          l.componentVariantId,
          l.variantName != null
              ? '${l.componentName} (${l.variantName})'
              : l.componentName,
          l.quantity,
        ),
      );
    }
  }

  Future<void> _add() async {
    final picked = await showDialog<_Line>(
      context: context,
      builder: (_) => _PickerDialog(excludeId: widget.product.id),
    );
    if (picked == null) return;
    if (!mounted) return;
    if (_wouldLoop(picked.productId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That product already contains this one — it would loop.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final dup =
        _lines
            .where(
              (l) =>
                  l.productId == picked.productId &&
                  l.variantId == picked.variantId,
            )
            .firstOrNull;
    setState(() {
      if (dup != null) {
        dup.qty++;
      } else {
        _lines.add(picked);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveRecipe(
        ref,
        parentProductId: widget.product.id,
        lines: [
          for (final l in _lines)
            RecipeDraftLine(l.productId, l.variantId, l.qty),
        ],
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save recipe (needs internet): $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Recipe: ${widget.product.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'When this product is sold, these items are deducted from stock.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            if (_lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No components yet. Add at least one.'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in _lines)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.label),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed:
                                l.qty > 1
                                    ? () => setState(() => l.qty--)
                                    : null,
                          ),
                          Text(
                            '${l.qty}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setState(() => l.qty++),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => setState(() => _lines.remove(l)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Component'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save Recipe'),
        ),
      ],
    );
  }
}

class _PickerDialog extends ConsumerStatefulWidget {
  final String excludeId;
  const _PickerDialog({required this.excludeId});

  @override
  ConsumerState<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends ConsumerState<_PickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productListProvider).asData?.value ?? [];
    final rows = <Widget>[];
    for (final p in products) {
      if (p.id == widget.excludeId || p.isCustom) continue;
      if (_q.isNotEmpty && !p.name.toLowerCase().contains(_q)) continue;
      if (p.variants.isEmpty) {
        rows.add(
          ListTile(
            dense: true,
            title: Text(p.name),
            onTap: () => Navigator.pop(context, _Line(p.id, null, p.name, 1)),
          ),
        );
      } else {
        for (final v in p.variants) {
          rows.add(
            ListTile(
              dense: true,
              title: Text('${p.name} (${v.name})'),
              onTap:
                  () => Navigator.pop(
                    context,
                    _Line(p.id, v.id, '${p.name} (${v.name})', 1),
                  ),
            ),
          );
        }
      }
    }
    return AlertDialog(
      title: const Text('Pick a component'),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search products',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            Expanded(child: ListView(children: rows)),
          ],
        ),
      ),
    );
  }
}
