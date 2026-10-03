import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import 'floor_plan_view.dart';
import '../../shared/widgets/app_colors.dart';

class TableSelector extends ConsumerStatefulWidget {
  const TableSelector({super.key});

  @override
  ConsumerState<TableSelector> createState() => _TableSelectorState();
}

class _TableSelectorState extends ConsumerState<TableSelector> {
  bool _expanded = true;

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetCtx).height * 0.6,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Select table',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              const Divider(height: 1),
              Expanded(
                child: FloorPlanView(
                  onSelectTable: (_) => Navigator.pop(sheetCtx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600 || size.height < 500;
    final selected =
        ref.watch(tableProvider.select((s) => s.selectedTableName));
    final panelHeight = (size.height * 0.28).clamp(140.0, 260.0);
    final showPlan = !compact && _expanded;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: compact
                ? _openSheet
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.table_restaurant_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    selected == null ? 'Select table' : 'Table $selected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected == null
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                  ),
                  if (selected != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        ref.read(tableProvider.notifier).clearSelection();
                        if (!compact) setState(() => _expanded = true);
                      },
                      child: const Icon(Icons.close,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    compact
                        ? Icons.chevron_right
                        : (_expanded ? Icons.expand_less : Icons.expand_more),
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: showPlan
                ? SizedBox(
                    height: panelHeight,
                    child: FloorPlanView(
                      onSelectTable: (_) => setState(() => _expanded = false),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}