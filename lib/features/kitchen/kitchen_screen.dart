// lib/features/kitchen/kitchen_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/order_provider.dart';
import '../../core/models/order.dart';
import '../../shared/widgets/app_colors.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(orderProvider);
    final notifier = ref.read(orderProvider.notifier);

    final pending =
        orders.where((o) => o.status == 'pending').toList();
    final preparing =
        orders.where((o) => o.status == 'preparing').toList();
    final ready =
        orders.where((o) => o.status == 'ready').toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Header ───────────────────────────────────────────
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

          // ── Columns ──────────────────────────────────────────
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.kitchen_outlined,
                            size: 48,
                            color: AppColors.textSecondary
                                .withOpacity(0.25)),
                        const SizedBox(height: 12),
                        const Text('No orders yet',
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
                        orders: pending,
                        notifier: notifier,
                      ),
                      _KitchenColumn(
                        title: 'Preparing',
                        color: AppColors.info,
                        orders: preparing,
                        notifier: notifier,
                      ),
                      _KitchenColumn(
                        title: 'Ready',
                        color: AppColors.success,
                        orders: ready,
                        notifier: notifier,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Column ────────────────────────────────────────────────────────────────────
class _KitchenColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<Order> orders;
  final OrderNotifier notifier;

  const _KitchenColumn({
    required this.title,
    required this.color,
    required this.orders,
    required this.notifier,
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13)),
                border: Border(
                    bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
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
                              color: AppColors.textSecondary
                                  .withOpacity(0.4))))
                  : ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _OrderCard(
                            order: orders[index],
                            notifier: notifier);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Order card ────────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final Order order;
  final OrderNotifier notifier;

  const _OrderCard({required this.order, required this.notifier});

  @override
  Widget build(BuildContext context) {
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
          // Order ID + total
          Row(
            children: [
              Text(order.id,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Text('₱${order.total.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),

          // Items
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
              )),

          const SizedBox(height: 10),

          // Action button
          SizedBox(
            width: double.infinity,
            height: 34,
            child: _actionButton(order, notifier),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(Order order, OrderNotifier notifier) {
    return switch (order.status) {
      'pending' => ElevatedButton(
          onPressed: () => notifier.updateStatus(order.id, 'preparing'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.zero,
          ),
          child: const Text('Start preparing',
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      'preparing' => ElevatedButton(
          onPressed: () => notifier.updateStatus(order.id, 'ready'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.zero,
          ),
          child: const Text('Mark ready',
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      'ready' => ElevatedButton(
          onPressed: () => notifier.removeOrder(order.id),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.textSecondary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.zero,
          ),
          child: const Text('Complete & remove',
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      _ => const SizedBox.shrink(),
    };
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
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              style: TextStyle(
                  color: color.withOpacity(0.8), fontSize: 11)),
        ],
      ),
    );
  }
}