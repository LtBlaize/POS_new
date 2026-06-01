// lib/features/tables/floor_plan_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import '../../shared/widgets/app_colors.dart';

class FloorPlanView extends ConsumerStatefulWidget {
  /// Called when user taps a free table to select it
  final ValueChanged<String>? onSelectTable;
  /// If true, tables are draggable (settings/edit mode)
  final bool editMode;

  const FloorPlanView({
    super.key,
    this.onSelectTable,
    this.editMode = false,
  });

  @override
  ConsumerState<FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends ConsumerState<FloorPlanView> {
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    final tableState = ref.watch(tableProvider);
    final tables = tableState.tables;
    final selected = tableState.selectedTableName;

    return Column(
      children: [
        if (widget.editMode && _dirty)
          Container(
            color: AppColors.warning.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.edit_location_outlined,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Layout changed — save to persist',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.warning)),
                ),
                TextButton(
                  onPressed: () async {
                    await ref.read(tableProvider.notifier).saveLayout();
                    if (mounted) setState(() => _dirty = false);
                  },
                  child: const Text('Save Layout'),
                ),
              ],
            ),
          ),
        Expanded(
          child: tables.isEmpty
              ? const Center(
                  child: Text('No tables set up yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)))
              : InteractiveViewer(
                  boundaryMargin: const EdgeInsets.all(200),
                  minScale: 0.5,
                  maxScale: 2.5,
                  child: SizedBox(
                    width: 1000,
                    height: 800,
                    child: Stack(
                      children: [
                        // Grid background
                        Positioned.fill(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        // Tables
                        ...tables.map((table) {
                          return _TableWidget(
                            key: ValueKey(table.uuid ?? table.name),
                            table: table,
                            isSelected: selected == table.name,
                            editMode: widget.editMode,
                            onTap: () {
                              if (widget.editMode) return;
                              if (table.status == TableStatus.occupied) {
                                _confirmFree(context, table.name);
                              } else {
                                ref
                                    .read(tableProvider.notifier)
                                    .selectTable(table.name);
                                widget.onSelectTable?.call(table.name);
                              }
                            },
                            onDragEnd: (x, y) {
                              ref
                                  .read(tableProvider.notifier)
                                  .moveTable(table.name, x, y);
                              setState(() => _dirty = true);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _confirmFree(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Free table?'),
        content: Text('Mark "$name" as available?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(tableProvider.notifier).freeTable(name);
            },
            child: const Text('Free Table',
                style: TextStyle(color: AppColors.success)),
          ),
        ],
      ),
    );
  }
}

// ── Table widget ──────────────────────────────────────────────────────────────

class _TableWidget extends StatefulWidget {
  final TableEntry table;
  final bool isSelected;
  final bool editMode;
  final VoidCallback onTap;
  final void Function(double x, double y) onDragEnd;

  const _TableWidget({
    super.key,
    required this.table,
    required this.isSelected,
    required this.editMode,
    required this.onTap,
    required this.onDragEnd,
  });

  @override
  State<_TableWidget> createState() => _TableWidgetState();
}

class _TableWidgetState extends State<_TableWidget> {
  late double _x;
  late double _y;

  @override
  void initState() {
    super.initState();
    _x = widget.table.x;
    _y = widget.table.y;
  }

  @override
  void didUpdateWidget(_TableWidget old) {
    super.didUpdateWidget(old);
    if (!widget.editMode) {
      _x = widget.table.x;
      _y = widget.table.y;
    }
  }

  Color get _bgColor {
    if (widget.isSelected) return AppColors.primary;
    if (widget.table.status == TableStatus.occupied)
      return AppColors.danger.withOpacity(0.15);
    return Colors.white;
  }

  Color get _borderColor {
    if (widget.isSelected) return AppColors.primary;
    if (widget.table.status == TableStatus.occupied)
      return AppColors.danger.withOpacity(0.6);
    return AppColors.divider;
  }

  Color get _textColor {
    if (widget.isSelected) return Colors.white;
    if (widget.table.status == TableStatus.occupied) return AppColors.danger;
    return AppColors.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.table.w;
    final h = widget.table.h;

    Widget tableBox = GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.table.status == TableStatus.occupied
                  ? Icons.people_outlined
                  : Icons.table_restaurant_outlined,
              size: 20,
              color: _textColor.withOpacity(0.7),
            ),
            const SizedBox(height: 4),
            Text(
              widget.table.name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _textColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.table.status == TableStatus.occupied
                  ? 'Busy'
                  : widget.isSelected
                      ? 'Selected'
                      : 'Free',
              style: TextStyle(
                  fontSize: 9,
                  color: _textColor.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );

    if (widget.editMode) {
      tableBox = Draggable(
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.7, child: tableBox),
        ),
        childWhenDragging: Opacity(opacity: 0.2, child: tableBox),
        onDragEnd: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final localPos = box.globalToLocal(details.offset);
          setState(() {
            _x = (_x + localPos.dx).clamp(0, 920);
            _y = (_y + localPos.dy).clamp(0, 720);
          });
          widget.onDragEnd(_x, _y);
        },
        child: tableBox,
      );
    }

    return Positioned(
      left: _x,
      top: _y,
      child: tableBox,
    );
  }
}

// ── Grid background painter ───────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.divider.withOpacity(0.5)
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}