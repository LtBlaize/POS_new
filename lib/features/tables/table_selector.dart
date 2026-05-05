import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import '../../shared/widgets/app_colors.dart';

class TableSelector extends ConsumerWidget {
  const TableSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableState = ref.watch(tableProvider);
    final tables = tableState.tables;
    final selectedName = tableState.selectedTableName;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'Table',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Expanded(
              child: tables.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'No tables set up yet',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      itemCount: tables.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final table = tables[index];
                        final isSelected = selectedName == table.name;
                        final isOccupied =
                            table.status == TableStatus.occupied;

                        Color bgColor;
                        Color borderColor;
                        Color textColor;

                        if (isSelected) {
                          bgColor = AppColors.primary;
                          borderColor = AppColors.primary;
                          textColor = Colors.white;
                        } else if (isOccupied) {
                          bgColor = AppColors.danger.withOpacity(0.08);
                          borderColor = AppColors.danger.withOpacity(0.4);
                          textColor = AppColors.danger;
                        } else {
                          bgColor = AppColors.surface;
                          borderColor = AppColors.divider;
                          textColor = AppColors.textSecondary;
                        }

                        return GestureDetector(
                          onTap: isOccupied
                              ? () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Free table?'),
                                      content: Text(
                                          'Mark "${table.name}" as available? Only do this when the customer has left.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Free Table',
                                              style: TextStyle(
                                                  color: Colors.green)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    ref
                                        .read(tableProvider.notifier)
                                        .freeTable(table.name);
                                  }
                                }
                              : () => ref
                                  .read(tableProvider.notifier)
                                  .selectTable(table.name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            constraints: const BoxConstraints(
                                minWidth: 56, maxWidth: 100),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: borderColor, width: 1.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  table.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  isOccupied
                                      ? 'busy'
                                      : isSelected
                                          ? 'sel'
                                          : 'free',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: textColor.withOpacity(0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Selected badge
            if (selectedName != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () =>
                      ref.read(tableProvider.notifier).clearSelection(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_restaurant_outlined,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '$selectedName  ✕',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
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
}