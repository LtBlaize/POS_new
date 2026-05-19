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
          final cached =
              ref.read(ordersStreamProvider).asData?.value ?? [];
          if (cached.isNotEmpty) {
            return _buildTabViews(cached);
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
                  onPressed: () =>
                      ref.invalidate(ordersStreamProvider),
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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  Color _accentColor(OrderStatus s, {bool isPaid = false}) =>
      switch (s) {
        OrderStatus.pending => const Color(0xFFF59E0B),
        OrderStatus.preparing => const Color(0xFF3B82F6),
        OrderStatus.ready => const Color(0xFF10B981),
        OrderStatus.completed =>
          isPaid ? const Color(0xFF6B7280) : const Color(0xFFEF4444),
        OrderStatus.cancelled => const Color(0xFF9CA3AF),
      };

  String _statusLabel(OrderStatus s, {bool isPaid = false}) =>
      switch (s) {
        OrderStatus.pending =>
          isPaid ? 'Paid · In Queue' : 'Unpaid · Pending',
        OrderStatus.preparing => 'Preparing',
        OrderStatus.ready => 'Ready to serve',
        OrderStatus.completed =>
          isPaid ? 'Paid · Completed' : 'Served · Unpaid',
        OrderStatus.cancelled => 'Cancelled',
      };

  /// Void is only shown for active (unpaid, non-cancelled) orders.
  bool get _canVoid =>
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.completed;

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
            color: Colors.black.withOpacity(0.04),
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
                            color: accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: accent.withOpacity(0.3)),
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
                                    color: accent.withOpacity(0.1),
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
                                if (canVoid) ...[
                                  const SizedBox(width: 6),
                                  _VoidItemButton(
                                    orderId: order.id,
                                    businessId: businessId,
                                    item: item,
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
                            ],
                          )
                        else if (order.paidAt == null &&
                            order.status != OrderStatus.cancelled)
                          _PayNowButton(
                              order: order,
                              featureManager: featureManager),
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
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
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
            color: AppColors.danger.withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
            border:
                Border.all(color: AppColors.danger.withOpacity(0.25)),
          ),
          child: Icon(Icons.remove_circle_outline,
              size: 14, color: AppColors.danger),
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
          cartNotifier.addProduct(item.product);
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