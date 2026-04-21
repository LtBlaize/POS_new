// lib/features/tables/table_selector.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import '../../shared/widgets/app_colors.dart';

class TableSelector extends ConsumerWidget {
  const TableSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tableProvider);
    final notifier = ref.read(tableProvider.notifier);
    final selected = notifier.selectedTable;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text('Table',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4)),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 12),
              itemCount: tables.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final table = tables[index];
                final isSelected = selected == table.number;
                final isOccupied =
                    table.status == TableStatus.occupied;
                final isReserved =
                    table.status == TableStatus.reserved;

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
                } else if (isReserved) {
                  bgColor = AppColors.warning.withOpacity(0.08);
                  borderColor = AppColors.warning.withOpacity(0.4);
                  textColor = AppColors.warning;
                } else {
                  bgColor = AppColors.surface;
                  borderColor = AppColors.divider;
                  textColor = AppColors.textSecondary;
                }

                return GestureDetector(
                  onTap: isOccupied
                      ? null
                      : () {
                          notifier.selectTable(table.number);
                          // Rebuild by triggering a state read
                          ref.invalidate(tableProvider);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 56,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor, width: 1.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${table.number}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: textColor)),
                        if (isOccupied)
                          Text('busy',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: textColor.withOpacity(0.7),
                                  fontWeight: FontWeight.w500))
                        else if (isReserved)
                          Text('rsv',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: textColor.withOpacity(0.7),
                                  fontWeight: FontWeight.w500))
                        else
                          Text('free',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: textColor.withOpacity(0.6),
                                  fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}