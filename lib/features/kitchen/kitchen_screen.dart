import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/order_provider.dart';
import '../../core/models/order.dart';
import '../../shared/widgets/app_colors.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.red))),
        data: (orders) {
          // Only show active kitchen orders
          final active = orders
              .where((o) =>
                  o.status == OrderStatus.pending ||
                  o.status == OrderStatus.preparing ||
                  o.status == OrderStatus.ready)
              .toList();

          final pending =
              active.where((o) => o.status == OrderStatus.pending).toList();
          final preparing =
              active.where((o) => o.status == OrderStatus.preparing).toList();
          final ready =
              active.where((o) => o.status == OrderStatus.ready).toList();

          return Column(
            children: [
              // ── Header ─────────────────────────────────────────────────
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Row(
                  children: [
                    const Text('Kitchen Display',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5)),
                    const Spacer(),
                    _KitchenStat(
                        label: 'Pending',
                        count: pending.length,
                        color: AppColors.warning),
                    const SizedBox(width: 12),
                    _KitchenStat(
                        label: 'Preparing',
                        count: preparing.length,
                        color: AppColors.info),
                    const SizedBox(width: 12),
                    _KitchenStat(
                        label: 'Ready',
                        count: ready.length,
                        color: AppColors.success),
                  ],
                ),
              ),

              // ── Columns ────────────────────────────────────────────────
              Expanded(
                child: active.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.kitchen_outlined,
                                size: 48,
                                color: AppColors.textSecondary
                                    .withOpacity(0.25)),
                            const SizedBox(height: 12),
                            const Text('No active orders',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 15)),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _KitchenColumn(
                              title: 'Pending',
                              color: AppColors.warning,
                              orders: pending),
                          _KitchenColumn(
                              title: 'Preparing',
                              color: AppColors.info,
                              orders: preparing),
                          _KitchenColumn(
                              title: 'Ready',
                              color: AppColors.success,
                              orders: ready),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Column ────────────────────────────────────────────────────────────────────

class _KitchenColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<Order> orders;

  const _KitchenColumn({
    required this.title,
    required this.color,
    required this.orders,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            // Column header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(
                    bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const Spacer(),
                  if (orders.isNotEmpty)
                    Text('${orders.length}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color)),
                ],
              ),
            ),

            // Order cards
            Expanded(
              child: orders.isEmpty
                  ? Center(
                      child: Text('No orders',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  AppColors.textSecondary.withOpacity(0.4))))
                  : ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _KitchenOrderCard(order: orders[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kitchen order card ────────────────────────────────────────────────────────

class _KitchenOrderCard extends ConsumerStatefulWidget {
  final Order order;
  const _KitchenOrderCard({required this.order});

  @override
  ConsumerState<_KitchenOrderCard> createState() =>
      _KitchenOrderCardState();
}

class _KitchenOrderCardState extends ConsumerState<_KitchenOrderCard> {
  bool _loading = false;

  Future<void> _advance() async {
    final next = switch (widget.order.status) {
      OrderStatus.pending   => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      OrderStatus.ready     => OrderStatus.completed,
      _                     => null,
    };
    if (next == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(orderServiceProvider).updateStatus(widget.order.id, next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    final (buttonLabel, buttonColor) = switch (order.status) {
      OrderStatus.pending   => ('Start preparing', AppColors.warning),
      OrderStatus.preparing => ('Mark ready',      AppColors.success),
      OrderStatus.ready     => ('Complete',        AppColors.textSecondary),
      _                     => ('',                Colors.transparent),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Order #${order.orderNumber}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const Spacer(),
              Text('₱${order.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),

          // Items — if loaded, show them; otherwise show placeholder
          if (order.items.isNotEmpty)
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Center(
                          child: Text('${item.quantity}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(item.product.name,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ))
          else
            const Text('Loading items...',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),

          const SizedBox(height: 10),

          // Action button
          if (buttonLabel.isNotEmpty)
            SizedBox(
              width: double.infinity,
              height: 34,
              child: _loading
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : ElevatedButton(
                      onPressed: _advance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(buttonLabel,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
            ),
        ],
      ),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _KitchenStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _KitchenStat(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          const SizedBox(width: 5),
          Text(label,
              style:
                  TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
        ],
      ),
    );
  }
}