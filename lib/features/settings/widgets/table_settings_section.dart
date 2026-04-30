import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tables/table_provider.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../shared/widgets/app_colors.dart';

class TableSettingsSection extends ConsumerStatefulWidget {
  const TableSettingsSection({super.key});

  @override
  ConsumerState<TableSettingsSection> createState() =>
      _TableSettingsSectionState();
}

class _TableSettingsSectionState extends ConsumerState<TableSettingsSection> {
  final _nameController = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addTable() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final tables = ref.read(tableProvider).tables;
    final duplicate = tables.any(
      (t) => t.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" already exists')),
      );
      return;
    }

    setState(() => _adding = true);
    try {
      final businessId =
          ref.read(profileProvider).asData?.value?.businessId;
      if (businessId == null) return;

      final client = ref.read(supabaseClientProvider);
      await client.from('restaurant_tables').insert({
        'business_id': businessId,
        'table_number': name,
        'is_active': true,
        'is_occupied': false,
      });

      _nameController.clear();
      await ref.read(tableProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableState = ref.watch(tableProvider);
    final tables = tableState.tables;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.table_restaurant_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Tables',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            Text('· ${tables.length} total',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 12),

        // Add table input
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add table',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'e.g. 1, Table 1, Bar, VIP',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: AppColors.divider),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _addTable(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _adding ? null : _addTable,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Add',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Table chips
        if (tableState.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (tables.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No tables yet.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tables.map((t) => _TableChip(table: t)).toList(),
          ),
      ],
    );
  }
}

class _TableChip extends ConsumerWidget {
  final TableEntry table;
  const _TableChip({required this.table});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOccupied = table.status == TableStatus.occupied;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOccupied
            ? AppColors.danger.withOpacity(0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOccupied
              ? AppColors.danger.withOpacity(0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            table.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color:
                  isOccupied ? AppColors.danger : AppColors.textPrimary,
            ),
          ),
          if (!isOccupied && table.uuid != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete table?'),
                    content: Text(
                        '"${table.name}" will be removed permanently.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete',
                              style:
                                  TextStyle(color: AppColors.danger))),
                    ],
                  ),
                );
                if (confirm == true && table.uuid != null) {
                  final client = ref.read(supabaseClientProvider);
                  await client
                      .from('restaurant_tables')
                      .update({'is_active': false}).eq('id', table.uuid!);
                  ref.read(tableProvider.notifier).refresh();
                }
              },
              child: const Icon(Icons.close,
                  size: 13, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}