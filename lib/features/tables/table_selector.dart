import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import 'floor_plan_view.dart';
import '../../shared/widgets/app_colors.dart';

class TableSelector extends ConsumerWidget {
  const TableSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableState = ref.watch(tableProvider);
    final selectedName = tableState.selectedTableName;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SizedBox(
        height: 340,
        child: Column(
          children: [
            // Selected badge row
            if (selectedName != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.table_restaurant_outlined,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Table $selectedName selected',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () =>
                          ref.read(tableProvider.notifier).clearSelection(),
                      child: const Icon(Icons.close,
                          size: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: FloorPlanView(
                onSelectTable: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}