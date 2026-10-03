// lib/features/tables/floor_plan_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import '../../shared/widgets/app_colors.dart';
import '../../core/models/cart_item.dart';
import '../../core/models/order.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/order_provider.dart';
import '../auth/auth_provider.dart';
import '../pos/dialogs/checkout_dialog.dart';
import 'open_tab_provider.dart';
import '../../core/providers/app_context_provider.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';

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
            color: AppColors.warning.withValues(alpha:0.1),
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
              : !widget.editMode
                  ? _buildFitted(tables, selected)
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
                                _showOccupiedSheet(table);
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

  void _handleTap(TableEntry table) {
    if (widget.editMode) return;
    if (table.status == TableStatus.occupied) {
      _confirmFree(context, table.name);
    } else {
      ref.read(tableProvider.notifier).selectTable(table.name);
      widget.onSelectTable?.call(table.name);
    }
  }

  /// View mode: crop to the tables' bounding box and scale down to fit.
  Widget _buildFitted(List<TableEntry> tables, String? selected) {
    const pad = 8.0;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final t in tables) {
      if (t.x < minX) minX = t.x;
      if (t.y < minY) minY = t.y;
      if (t.x + t.w > maxX) maxX = t.x + t.w;
      if (t.y + t.h > maxY) maxY = t.y + t.h;
    }
    final width = maxX - minX + pad * 2;
    final height = maxY - minY + pad * 2;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              for (final table in tables)
                _TableWidget(
                  key: ValueKey(table.uuid ?? table.name),
                  table: table.copyWith(
                    x: table.x - minX + pad,
                    y: table.y - minY + pad,
                  ),
                  isSelected: selected == table.name,
                  editMode: false,
                  onTap: () => _handleTap(table),
                  onDragEnd: (_, _) {},
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOccupiedSheet(TableEntry table) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Table ${table.name}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.add_shopping_cart),
              title: const Text('Add items to tab'),
              onTap: () => Navigator.pop(ctx, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Pay'),
              onTap: () => Navigator.pop(ctx, 'pay'),
            ),
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Free table'),
              onTap: () => Navigator.pop(ctx, 'free'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        await _startAddToTab(table);
      case 'pay':
        await _startPay(table);
      case 'free':
        _confirmFree(context, table.name);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Latest unpaid, non-cancelled order for this table (online lookup).
    /// Latest unpaid, non-cancelled order for this table. Online lookup first,
  /// local cache when offline or on a network failure.
  Future<Map<String, dynamic>?> _findOpenOrder(TableEntry table) async {
    final uuid = table.uuid;
    if (uuid == null) return null;
    if (ref.read(isOnlineProvider)) {
      try {
        return await ref
            .read(supabaseClientProvider)
            .from('orders')
            .select('id, order_number, total_amount')
            .eq('table_id', uuid)
            .isFilter('paid_at', null)
            .neq('status', 'cancelled')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {/* fall through to local */}
    }
    final businessId = ref.read(activeBusinessIdProvider);
    if (businessId == null) return null;
    final local = await ref.read(localDbServiceProvider).getOrders(businessId);
    final open = local
        .where((o) =>
            o.tableId == uuid &&
            o.paidAt == null &&
            o.status != OrderStatus.cancelled)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (open.isEmpty) return null;
    final o = open.first;
    return {
      'id': o.id,
      'order_number': o.orderNumber,
      'total_amount': o.totalAmount,
    };
  }

  Future<void> _startAddToTab(TableEntry table) async {
    if (ref.read(cartProvider).isNotEmpty) {
      _toast('Send or hold the current cart first.');
      return;
    }
    final row = await _findOpenOrder(table);
    if (!mounted) return;
    if (row == null) {
      _toast('No open order found for Table ${table.name} (needs a connection).');
      return;
    }
    ref.read(openTabProvider.notifier).state = OpenTab(
      orderId: row['id'] as String,
      orderNumber: row['order_number'] as int,
      tableName: table.name,
      existingTotal: (row['total_amount'] as num).toDouble(),
    );
    if (ref.read(tableProvider).selectedTableName != table.name) {
      ref.read(tableProvider.notifier).selectTable(table.name);
    }
    widget.onSelectTable?.call(table.name); // closes sheet / collapses panel
  }

  Future<void> _startPay(TableEntry table) async {
    final row = await _findOpenOrder(table);
    if (!mounted) return;
    if (row == null) {
      _toast('No open order found for Table ${table.name} (needs a connection).');
      return;
    }
    final orderId = row['id'] as String;
    try {
      // Prefer the stream's copy: promo lines are already grouped there.
      Order? order = ref
          .read(ordersStreamProvider)
          .asData
          ?.value
          .where((o) => o.id == orderId)
          .firstOrNull;
      if (order == null || order.items.isEmpty) {
        order = await ref.read(orderServiceProvider).fetchOrderWithItems(orderId);
      }
      final cart = ref.read(cartProvider.notifier);
      cart.clear();
      cart.loadItems(
        order.items,
        orderDiscountAmount: order.discountAmount,
        orderDiscountType: DiscountType.fixed,
        tipAmount: order.tipAmount,
      );
      if (ref.read(tableProvider).selectedTableName != table.name) {
        ref.read(tableProvider.notifier).selectTable(table.name);
      }
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => CheckoutDialog(
          featureManager: ref.read(featureManagerProvider),
          existingOrderId: orderId,
        ),
      );
    } catch (e) {
      _toast('Could not open payment: $e');
    }
  }

  void _confirmFree(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Free table?'),
        content: Text(
          'Table "$name" may still have an unpaid order. '
          'Freeing it will not cancel or pay that order — it stays open in '
          'Orders → Active. Mark as available anyway?',
        ),
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
    if (widget.table.status == TableStatus.occupied) {
      return AppColors.danger.withValues(alpha: 0.15);
    }
    return Colors.white;
  }

  Color get _borderColor {
    if (widget.isSelected) return AppColors.primary;
    if (widget.table.status == TableStatus.occupied) {
      return AppColors.danger.withValues(alpha: 0.6);
    }
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
              color: Colors.black.withValues(alpha:0.06),
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
              color: _textColor.withValues(alpha:0.7),
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
                  color: _textColor.withValues(alpha:0.7)),
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
              final canvas = context.findAncestorRenderObjectOfType<RenderBox>();
              if (canvas == null) return;
              final localPos = canvas.globalToLocal(details.offset);
              setState(() {
                _x = localPos.dx.clamp(0, 920);
                _y = localPos.dy.clamp(0, 720);
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
      ..color = AppColors.divider.withValues(alpha:0.5)
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