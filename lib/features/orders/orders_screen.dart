// lib/features/orders/orders_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/order.dart';
import '../../core/models/staff.dart';
import '../../core/providers/order_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/services/feature_manager.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/pos/dialogs/checkout_dialog.dart';
import '../../features/tables/table_provider.dart';
import '../../shared/widgets/app_colors.dart';
import 'widgets/void_item_dialog.dart';
import '../../core/models/cart_item.dart';
import '../../core/services/receipt_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/thermal_print_service.dart';
import '../../core/providers/app_context_provider.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  const OrdersScreen({super.key, required this.featureManager});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersStreamProvider);
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          fontSize: isNarrow ? 16 : 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: TextStyle(
            fontSize: isNarrow ? 12 : 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: ordersAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          final businessId = ref.read(activeBusinessIdProvider);
          if (businessId != null) {
            return FutureBuilder<List<Order>>(
              future: ref.read(localDbServiceProvider).getOrders(businessId),
              builder: (context, snap) {
                final cached = snap.data ?? [];
                if (cached.isNotEmpty) return _buildTabViews(cached);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('Error: $e',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.invalidate(ordersStreamProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              },
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('Offline — no cached orders yet',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(ordersStreamProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        },
        data: (orders) => _buildTabViews(orders),
      ),
    );
  }

  Widget _buildTabViews(List<Order> orders) {
    final active = _filterActive(orders);
    final completed = _filterCompleted(orders);
    return TabBarView(
      controller: _tabs,
      children: [
        _OrderList(orders: orders, featureManager: widget.featureManager),
        _OrderList(orders: active, featureManager: widget.featureManager),
        _OrderList(orders: completed, featureManager: widget.featureManager),
      ],
    );
  }

  List<Order> _filterActive(List<Order> orders) => orders
      .where((o) =>
          o.status == OrderStatus.pending ||
          o.status == OrderStatus.preparing ||
          o.status == OrderStatus.ready ||
          (o.status == OrderStatus.completed && o.paidAt == null))
      .toList();

  List<Order> _filterCompleted(List<Order> orders) => orders
      .where((o) =>
          (o.status == OrderStatus.completed && o.paidAt != null) ||
          o.status == OrderStatus.cancelled)
      .toList();
}

// ── Order list ────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final FeatureManager featureManager;
  const _OrderList({required this.orders, required this.featureManager});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Text('No orders here.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final width = MediaQuery.sizeOf(context).width;

    if (width >= 900) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
        ),
        itemCount: orders.length,
        itemBuilder: (_, i) => _OrderCard(
          key: ValueKey('${orders[i].id}-${orders[i].status}'),
          order: orders[i],
          featureManager: featureManager,
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(width < 600 ? 12 : 16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _OrderCard(
        key: ValueKey('${orders[i].id}-${orders[i].status}'),
        order: orders[i],
        featureManager: featureManager,
      ),
    );
  }
}

// ── Order card ────────────────────────────────────────────────────────────────

class _OrderCard extends ConsumerWidget {
  final Order order;
  final FeatureManager featureManager;
  const _OrderCard(
      {super.key, required this.order, required this.featureManager});

  Color _accentColor(OrderStatus s, {bool isPaid = false}) {
    final hasKitchen = featureManager.hasFeature('kitchen');
    return switch (s) {
        OrderStatus.pending => (isPaid && !hasKitchen)
            ? const Color(0xFF6B7280)
            : const Color(0xFFF59E0B),
        OrderStatus.preparing => const Color(0xFF3B82F6),
        OrderStatus.ready => const Color(0xFF10B981),
        OrderStatus.completed =>
          isPaid ? const Color(0xFF6B7280) : const Color(0xFFEF4444),
        OrderStatus.cancelled => const Color(0xFF9CA3AF),
      };
  }

  String _statusLabel(OrderStatus s, {bool isPaid = false}) {
    final hasKitchen = featureManager.hasFeature('kitchen');
    return switch (s) {
      OrderStatus.pending => isPaid
          ? (hasKitchen ? 'Paid · In Queue' : 'Completed')
          : 'Unpaid · Pending',
      OrderStatus.preparing => 'Preparing',
      OrderStatus.ready => 'Ready to serve',
      OrderStatus.completed =>
        isPaid ? 'Paid · Completed' : 'Served · Unpaid',
      OrderStatus.cancelled => 'Cancelled',
    };
  }

  /// Void item is only shown for active (unpaid, non-cancelled) orders.
  bool get _canVoid =>
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.completed;

  /// Void entire order — same condition plus order must have items.
  bool get _canVoidOrder =>
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.completed &&
      order.items.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent =
        _accentColor(order.status, isPaid: order.paidAt != null);
    final isPaid = order.paidAt != null;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    // Determine if current staff can void (manager / owner only)
    final activeStaff = ref.watch(activeStaffProvider);
    final canVoid = _canVoid &&
        activeStaff != null &&
        (activeStaff.role == StaffRole.owner ||
            activeStaff.role == StaffRole.manager);

    // Fetch businessId for void service call
    final profile = ref.watch(profileProvider).asData?.value;
    final businessId = profile?.businessId ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent bar
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12)),
              ),
            ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isNarrow ? 10 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Order #${order.orderNumber}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: isNarrow ? 13 : 15,
                              color: AppColors.textPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: accent.withValues(alpha:0.3)),
                          ),
                          child: Text(
                            _statusLabel(order.status,
                                isPaid: order.paidAt != null),
                            style: TextStyle(
                                fontSize: isNarrow ? 10 : 11,
                                fontWeight: FontWeight.w700,
                                color: accent),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 3),
                    Text(
                      _formatTime(order.createdAt),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),

                    const SizedBox(height: 10),

                    // Items — with void button when allowed
                    if (order.items.isNotEmpty) ...[
                      ...order.items.map((item) => Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha:0.1),
                                    borderRadius:
                                        BorderRadius.circular(5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${item.quantity}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: accent),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    item.product.name,
                                    style: TextStyle(
                                        fontSize: isNarrow ? 12 : 13,
                                        color: AppColors.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '₱${item.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
                                ),
                                // ── Void button ───────────────────
                                // Promo lines can't be safely voided item-
                                // by-item — no clean way to isolate "this
                                // cart line" in local storage, and voiding
                                // one component out of a promo is an
                                // unresolved product question (see
                                // orders_screen notes). Void the whole
                                // order instead.
                                if (canVoid && !item.isPromo) ...[
                                  const SizedBox(width: 6),
                                  _VoidItemButton(
                                    orderId: order.id,
                                    businessId: businessId,
                                    item: item,
                                  ),
                                ] else if (canVoid && item.isPromo) ...[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message:
                                        'Promo items can\'t be voided individually — use "Void Order" below.',
                                    child: Icon(Icons.lock_outline,
                                        size: 14,
                                        color: AppColors.textSecondary
                                            .withValues(alpha: 0.4)),
                                  ),
                                ],
                              ],
                            ),
                          )),
                      const Divider(height: 14),
                    ],

                    // Footer
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Total: ₱${order.totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: isNarrow ? 13 : 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        if (isPaid && order.paymentMethod != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle,
                                  size: 13,
                                  color: Color(0xFF6B7280)),
                              const SizedBox(width: 4),
                              Text(
                                order.paymentMethod!.value
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280)),
                              ),
                              const SizedBox(width: 8),
                              _ReprintButton(order: order),
                            ],
                          )
                        else if (order.paidAt == null &&
                            order.status != OrderStatus.cancelled) ...[
                          if (order.tableId != null)
                            _PrintBillButton(order: order),
                          const SizedBox(width: 8),
                          _PayNowButton(
                              order: order,
                              featureManager: featureManager),
                        ],
                        if (_canVoidOrder &&
                            activeStaff != null &&
                            (activeStaff.role == StaffRole.owner ||
                                activeStaff.role == StaffRole.manager)) ...[
                          const SizedBox(width: 8),
                          _VoidOrderButton(
                            order: order,
                            businessId: businessId,
                            staffId: activeStaff.id,
                            staffName: activeStaff.name,
                          ),
                        ],
                      ],
                    ),

                    if (isPaid &&
                        order.paymentMethod == PaymentMethod.cash &&
                        order.amountTendered != null &&
                        order.changeAmount != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Tendered: ₱${order.amountTendered!.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Change: ₱${order.changeAmount!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}

// ── Void item button ──────────────────────────────────────────────────────────

class _VoidItemButton extends ConsumerWidget {
  final String orderId;
  final String businessId;
  final CartItem item;

  const _VoidItemButton({
    required this.orderId,
    required this.businessId,
    required this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final result = await showVoidItemDialog(
          context: context,
          ref: ref,
          orderId: orderId,
          businessId: businessId,
          item: item,
        );

        if (result != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item.product.name} voided — '
                    '${result.record.reason}',
                  ),
                ),
              ]),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      },
      child: Tooltip(
        message: 'Void this item',
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(7),
            border:
                Border.all(color: AppColors.danger.withValues(alpha:0.25)),
          ),
          child: Icon(Icons.remove_circle_outline,
              size: 14, color: AppColors.danger),
        ),
      ),
    );
  }
}

// ── Void Order button ─────────────────────────────────────────────────────────

class _VoidOrderButton extends ConsumerStatefulWidget {
  final Order order;
  final String businessId;
  final String staffId;
  final String staffName;

  const _VoidOrderButton({
    required this.order,
    required this.businessId,
    required this.staffId,
    required this.staffName,
  });

  @override
  ConsumerState<_VoidOrderButton> createState() => _VoidOrderButtonState();
}

class _VoidOrderButtonState extends ConsumerState<_VoidOrderButton> {
  bool _loading = false;

  Future<void> _confirmVoid() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Entire Order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will cancel Order #${widget.order.orderNumber} '
              'and reverse all inventory. This cannot be undone.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Customer cancelled',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Void Order'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim().isEmpty
        ? 'Voided by staff'
        : reasonController.text.trim();

    setState(() => _loading = true);
    try {
      await ref.read(orderServiceProvider).voidOrder(
            orderId: widget.order.id,
            businessId: widget.businessId,
            reason: reason,
            voidedByStaffId: widget.staffId,
            voidedByStaffName: widget.staffName,
            items: widget.order.items,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Order #${widget.order.orderNumber} voided'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return GestureDetector(
      onTap: _confirmVoid,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha:0.25)),
        ),
        child: const Text(
          'Void Order',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.red),
        ),
      ),
    );
  }
}

// ── Reprint button ────────────────────────────────────────────────────────────

class _ReprintButton extends ConsumerStatefulWidget {
  final Order order;
  const _ReprintButton({required this.order});

  @override
  ConsumerState<_ReprintButton> createState() => _ReprintButtonState();
}

class _ReprintButtonState extends ConsumerState<_ReprintButton> {
  bool _loading = false;

  Future<void> _reprint() async {
    setState(() => _loading = true);
    try {
      final receiptService = ref.read(receiptServiceProvider);
      final receipt =
          await receiptService.fetchReceiptForOrder(widget.order.id);

      if (!mounted) return;

      if (receipt == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No receipt found for this order.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show receipt preview dialog
      await showDialog(
        context: context,
        builder: (ctx) => _ReceiptPreviewDialog(
          receipt: receipt,
          order: widget.order,
          onPrint: () async {
            await ThermalPrintService.printReceipt(
              order: widget.order,
              tendered: widget.order.amountTendered ?? widget.order.totalAmount,
              change: widget.order.changeAmount ?? 0.0,
              businessName: receipt['business_name'] as String? ?? '',
            );
            await receiptService.markReprinted(receipt['id'] as String);
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Tooltip(
      message: 'Reprint receipt',
      child: GestureDetector(
        onTap: _reprint,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Icon(Icons.receipt_outlined,
              size: 14, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ── Receipt preview dialog ────────────────────────────────────────────────────

class _ReceiptPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final Order order;
  final Future<void> Function() onPrint;

  const _ReceiptPreviewDialog({
    required this.receipt,
    required this.order,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    final reprintCount = receipt['reprint_count'] as int? ?? 0;
    final issuedAt = receipt['issued_at'] != null
        ? DateTime.parse(receipt['issued_at'] as String).toLocal()
        : order.createdAt;

    String fmt(DateTime dt) {
      final h = dt.hour > 12
          ? dt.hour - 12
          : dt.hour == 0
              ? 12
              : dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.month}/${dt.day}/${dt.year} $h:$m $period';
    }

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1F2937),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      receipt['receipt_number'] as String? ??
                          'Receipt',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (reprintCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Reprint #$reprintCount',
                        style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Receipt body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Business name
                  Center(
                    child: Text(
                      receipt['business_name'] as String? ??
                          'My Business',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (receipt['business_address'] != null) ...[
                    const SizedBox(height: 2),
                    Center(
                      child: Text(
                        receipt['business_address'] as String,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Order info
                  _ReceiptLine('Order #',
                      '${order.orderNumber}'),
                  _ReceiptLine('Date', fmt(issuedAt)),
                  if (order.paymentMethod != null)
                    _ReceiptLine('Payment',
                        order.paymentMethod!.value.toUpperCase()),
                  if (receipt['reference_number'] != null)
                    _ReceiptLine('Ref #',
                        receipt['reference_number'] as String),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Items
                  ...order.items.map((item) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text('${item.quantity}×',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color:
                                        AppColors.textSecondary)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(item.product.name,
                                  style: const TextStyle(
                                      fontSize: 12)),
                            ),
                            Text(
                              '₱${item.total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Totals
                  if (order.discountAmount > 0)
                    _ReceiptLine('Discount',
                        '−₱${order.discountAmount.toStringAsFixed(2)}'),
                  if (order.taxAmount > 0)
                    _ReceiptLine('Tax',
                        '₱${order.taxAmount.toStringAsFixed(2)}'),
                  _ReceiptLine(
                    'Total',
                    '₱${order.totalAmount.toStringAsFixed(2)}',
                    bold: true,
                  ),
                  if (order.amountTendered != null)
                    _ReceiptLine('Tendered',
                        '₱${order.amountTendered!.toStringAsFixed(2)}'),
                  if (order.changeAmount != null)
                    _ReceiptLine('Change',
                        '₱${order.changeAmount!.toStringAsFixed(2)}'),

                  if (receipt['footer_text'] != null) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        receipt['footer_text'] as String,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        await onPrint();
                        nav.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Receipt sent to printer'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      },
                      icon: const Icon(Icons.print_outlined,
                          size: 16),
                      label: const Text('Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF1F2937),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _ReceiptLine(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: bold
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: bold
                      ? FontWeight.w700
                      : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold
                      ? FontWeight.w800
                      : FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Print Bill button ─────────────────────────────────────────────────────────

class _PrintBillButton extends ConsumerStatefulWidget {
  final Order order;
  const _PrintBillButton({required this.order});

  @override
  ConsumerState<_PrintBillButton> createState() => _PrintBillButtonState();
}

class _PrintBillButtonState extends ConsumerState<_PrintBillButton> {
  bool _loading = false;

  Future<void> _printBill() async {
    setState(() => _loading = true);
    try {
      final profile = ref.read(profileProvider).asData?.value;
      final businessName = profile?.fullName ?? 'Restaurant';

      await ThermalPrintService.printBill(
        order: widget.order,
        businessName: businessName,
        is58mm: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.print_outlined, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Bill sent to printer'),
            ]),
            backgroundColor: const Color(0xFF1F2937),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Tooltip(
      message: 'Print bill',
      child: GestureDetector(
        onTap: _printBill,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF1F2937).withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.receipt_long_outlined,
                  size: 13, color: Color(0xFF1F2937)),
              SizedBox(width: 5),
              Text(
                'Bill',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pay Now button (unchanged from original) ──────────────────────────────────
class _PayNowButton extends ConsumerStatefulWidget {
  final Order order;
  final FeatureManager featureManager;
  const _PayNowButton({required this.order, required this.featureManager});

  @override
  ConsumerState<_PayNowButton> createState() => _PayNowButtonState();
}

class _PayNowButtonState extends ConsumerState<_PayNowButton> {
  bool _loading = false;

  Future<void> _openCheckout() async {
    setState(() => _loading = true);
    try {
      Order order = widget.order;
      if (order.items.isEmpty) {
        order = await ref
            .read(orderServiceProvider)
            .fetchOrderWithItems(order.id);
      }

      final cartNotifier = ref.read(cartProvider.notifier);
      cartNotifier.clear();
      for (final item in order.items) {
        for (var i = 0; i < item.quantity; i++) {
          cartNotifier.addProduct(item.product, variant: item.selectedVariant);
        }
      }

      if (order.tableId != null) {
        final tables = ref.read(tableProvider).tables;
        final match =
            tables.where((t) => t.uuid == order.tableId).toList();
        if (match.isNotEmpty) {
          ref
              .read(tableProvider.notifier)
              .selectTable(match.first.name);
        }
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => CheckoutDialog(
          featureManager: widget.featureManager,
          existingOrderId: order.id,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    }

    return GestureDetector(
      onTap: _openCheckout,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Pay Now',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}