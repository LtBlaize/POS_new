import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings_provider.dart';
import '../../tables/table_provider.dart';
import '../../../shared/widgets/app_colors.dart';

class TableSettingsSection extends ConsumerStatefulWidget {
  const TableSettingsSection({super.key});

  @override
  ConsumerState<TableSettingsSection> createState() =>
      _TableSettingsSectionState();
}

class _TableSettingsSectionState extends ConsumerState<TableSettingsSection> {
  int _addCount = 1;
  String? _selectedRoomId;

  @override
  Widget build(BuildContext context) {
    final tableState = ref.watch(tableProvider);
    final settingsState = ref.watch(settingsProvider);
    final tables = tableState.tables;
    final rooms = settingsState.rooms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────────────
        _SectionHeader(
          icon: Icons.table_restaurant_outlined,
          title: 'Tables',
          subtitle: '${tables.length} total',
        ),
        const SizedBox(height: 12),

        // ── Add tables row ──────────────────────────────────────────────────
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
              const Text(
                'Add tables',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Count stepper
                  _CountStepper(
                    value: _addCount,
                    onChanged: (v) => setState(() => _addCount = v),
                  ),
                  const SizedBox(width: 12),

                  // Room picker (only shows if rooms exist)
                  if (rooms.isNotEmpty) ...[
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedRoomId,
                          hint: const Text('No room',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                          isDense: true,
                          borderRadius: BorderRadius.circular(10),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No room',
                                  style: TextStyle(fontSize: 13)),
                            ),
                            ...rooms.map((r) => DropdownMenuItem<String?>(
                                  value: r.id,
                                  child: Text(r.name,
                                      style: const TextStyle(fontSize: 13)),
                                )),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedRoomId = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Add button
                  ElevatedButton(
                    onPressed: () async {
                      await ref
                          .read(settingsProvider.notifier)
                          .addTables(_addCount, _selectedRoomId);
                      ref.read(tableProvider.notifier).refresh();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Add',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Table list ──────────────────────────────────────────────────────
        if (tableState.isLoading)
          const Center(child: CircularProgressIndicator())
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

// ── Table chip with delete ────────────────────────────────────────────────────
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
            'T${table.number}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isOccupied ? AppColors.danger : AppColors.textPrimary,
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
                        'Table ${table.number} will be removed. This cannot be undone.'),
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
                if (confirm == true) {
                  await ref
                      .read(settingsProvider.notifier)
                      .deleteTable(table.uuid!);
                  ref.read(tableProvider.notifier).refresh();
                }
              },
              child: const Icon(Icons.close, size: 13,
                  color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Count stepper ─────────────────────────────────────────────────────────────
class _CountStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _CountStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
            icon: Icons.remove,
            onTap: value > 1 ? () => onChanged(value - 1) : null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$value',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ),
        _StepBtn(
            icon: Icons.add,
            onTap: value < 50 ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: onTap != null ? AppColors.surface : AppColors.divider,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon,
            size: 15,
            color: onTap != null
                ? AppColors.textPrimary
                : AppColors.textSecondary),
      ),
    );
  }
}// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text('· $subtitle',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}