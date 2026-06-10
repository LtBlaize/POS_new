// lib/features/inventory/widgets/category_management_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../shared/widgets/app_colors.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final categoryListProvider =
    StateNotifierProvider<CategoryListNotifier,
        AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final profile = ref.watch(profileProvider).asData?.value;
  return CategoryListNotifier(
    client: ref.watch(supabaseClientProvider),
    businessId: profile?.businessId,
  );
});

class CategoryListNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final dynamic _client;
  final String? _businessId;

  CategoryListNotifier({required dynamic client, required String? businessId})
      : _client = client,
        _businessId = businessId,
        super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    if (_businessId == null) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      final rows = await _client
          .from('categories')
          .select('id, name, icon, sort_order, is_active')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('sort_order')
          .order('name');
      state = AsyncValue.data(
          List<Map<String, dynamic>>.from(rows as List));
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> add(String name, String? icon) async {
    if (_businessId == null) return;
    final current = state.asData?.value ?? [];
    final maxSort = current.isEmpty
        ? 0
        : current
            .map((c) => c['sort_order'] as int? ?? 0)
            .reduce((a, b) => a > b ? a : b);
    await _client.from('categories').insert({
      'business_id': _businessId,
      'name': name.trim(),
      'icon': icon?.trim().isEmpty == true ? null : icon?.trim(),
      'sort_order': maxSort + 1,
      'is_active': true,
    });
    await load();
  }

  Future<void> rename(String id, String name, String? icon) async {
    await _client.from('categories').update({
      'name': name.trim(),
      'icon': icon?.trim().isEmpty == true ? null : icon?.trim(),
    }).eq('id', id);
    await load();
  }

  Future<void> reorder(String id, int newSortOrder) async {
    await _client
        .from('categories')
        .update({'sort_order': newSortOrder}).eq('id', id);
    await load();
  }

  Future<void> delete(String id) async {
    // Soft-delete — products with this category_id keep working,
    // category just stops appearing in filters and add-product dropdown.
    await _client
        .from('categories')
        .update({'is_active': false}).eq('id', id);
    await load();
  }
}

// ── Dialog entry point ────────────────────────────────────────────────────────

Future<void> showCategoryManagementDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const _CategoryManagementDialog(),
  );
}

class _CategoryManagementDialog extends ConsumerWidget {
  const _CategoryManagementDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider);

    return Dialog(
      backgroundColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text('Manage Categories',
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

            // ── Body ─────────────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: categoriesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e',
                      style: const TextStyle(color: AppColors.danger)),
                ),
                data: (categories) => categories.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'No categories yet.\nAdd your first one below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13),
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: categories.length,
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) newIndex--;
                          final notifier =
                              ref.read(categoryListProvider.notifier);
                          // Swap sort_order values
                          final moved = categories[oldIndex];
                          final target = categories[newIndex];
                          final movedOrder = moved['sort_order'] as int? ?? oldIndex;
                          final targetOrder = target['sort_order'] as int? ?? newIndex;
                          await Future.wait([
                            notifier.reorder(moved['id'] as String, targetOrder),
                            notifier.reorder(target['id'] as String, movedOrder),
                          ]);
                        },
                        itemBuilder: (_, i) => _CategoryTile(
                          key: ValueKey(categories[i]['id']),
                          category: categories[i],
                          onRename: (name, icon) => ref
                              .read(categoryListProvider.notifier)
                              .rename(
                                  categories[i]['id'] as String,
                                  name,
                                  icon),
                          onDelete: () => _confirmDelete(
                              context, ref, categories[i]),
                        ),
                      ),
              ),
            ),

            const Divider(height: 1),

            // ── Add new category ──────────────────────────────────────
            _AddCategoryRow(
              onAdd: (name, icon) =>
                  ref.read(categoryListProvider.notifier).add(name, icon),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref,
      Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text(
          'Delete "${category['name']}"? Products in this category '
          'will keep their data but the category will no longer appear.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(categoryListProvider.notifier)
                  .delete(category['id'] as String);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Category tile ─────────────────────────────────────────────────────────────

class _CategoryTile extends StatefulWidget {
  final Map<String, dynamic> category;
  final Future<void> Function(String name, String? icon) onRename;
  final VoidCallback onDelete;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _editing = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _iconCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.category['name'] as String);
    _iconCtrl = TextEditingController(
        text: widget.category['icon'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onRename(_nameCtrl.text, _iconCtrl.text);
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: _editing ? _editRow() : _displayRow(),
    );
  }

  Widget _displayRow() {
    final icon = widget.category['icon'] as String?;
    return Row(
      children: [
        const Icon(Icons.drag_handle,
            size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        if (icon != null && icon.isNotEmpty) ...[
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            widget.category['name'] as String,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _editing = true),
          icon: const Icon(Icons.edit_outlined, size: 16),
          color: AppColors.textSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: widget.onDelete,
          icon: const Icon(Icons.delete_outline, size: 16),
          color: AppColors.danger,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _editRow() {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: TextField(
            controller: _iconCtrl,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '🍔',
              hintStyle: const TextStyle(fontSize: 16),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Category name',
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        if (_saving)
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check_circle,
                color: AppColors.success, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => setState(() => _editing = false),
            icon: const Icon(Icons.cancel_outlined,
                color: AppColors.textSecondary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }
}

// ── Add category row ──────────────────────────────────────────────────────────

class _AddCategoryRow extends StatefulWidget {
  final Future<void> Function(String name, String? icon) onAdd;
  const _AddCategoryRow({required this.onAdd});

  @override
  State<_AddCategoryRow> createState() => _AddCategoryRowState();
}

class _AddCategoryRowState extends State<_AddCategoryRow> {
  final _nameCtrl = TextEditingController();
  final _iconCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onAdd(_nameCtrl.text, _iconCtrl.text);
      _nameCtrl.clear();
      _iconCtrl.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: TextField(
              controller: _iconCtrl,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '🍔',
                hintStyle: const TextStyle(fontSize: 16),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'New category name',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _saving ? null : _add,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Add',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}