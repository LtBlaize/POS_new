import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/order_provider.dart';
import '../../core/models/order.dart';
import '../../shared/widgets/app_colors.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error loading orders: $e',
              style: const TextStyle(color: Colors.red)),
        ),
        data: (orders) => orders.isEmpty
            ? const Center(
                child: Text('No orders yet.',
                    style: TextStyle(color: AppColors.textSecondary)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _OrderCard(order: orders[index]),
              ),
      ),
    );
  }
}

// ── Order card ────────────────────────────────────────────────────────────────

class _OrderCard extends ConsumerWidget {
  final Order order;
  const _OrderCard({required this.order});

  Color _statusColor(OrderStatus status) => switch (status) {
        OrderStatus.pending   => Colors.orange,
        OrderStatus.preparing => Colors.blue,
        OrderStatus.ready     => Colors.green,
        OrderStatus.completed => Colors.grey,
        OrderStatus.cancelled => Colors.red,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(orderServiceProvider);

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Order #${order.orderNumber}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    order.status.value.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: _statusColor(order.status),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _formatTime(order.createdAt),
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),

            // ── Items ────────────────────────────────────────────────────
            if (order.items.isNotEmpty) ...[
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text('${item.quantity}×  ${item.product.name}',
                            style: const TextStyle(fontSize: 13)),
                        const Spacer(),
                        Text('₱${item.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  )),
              const Divider(height: 16),
            ],

            // ── Footer row ───────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Total: ₱${order.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _StatusActions(order: order, service: service),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}

// ── Status action buttons ─────────────────────────────────────────────────────

class _StatusActions extends StatefulWidget {
  final Order order;
  final OrderService service;
  const _StatusActions({required this.order, required this.service});

  @override
  State<_StatusActions> createState() => _StatusActionsState();
}

class _StatusActionsState extends State<_StatusActions> {
  bool _loading = false;

  Future<void> _update(OrderStatus next) async {
    setState(() => _loading = true);
    try {
      await widget.service.updateStatus(widget.order.id, next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
        width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return switch (widget.order.status) {
      OrderStatus.pending => ElevatedButton(
          onPressed: () => _update(OrderStatus.preparing),
          child: const Text('Accept'),
        ),
      OrderStatus.preparing => ElevatedButton(
          onPressed: () => _update(OrderStatus.ready),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Mark Ready'),
        ),
      OrderStatus.ready => ElevatedButton(
          onPressed: () => _update(OrderStatus.completed),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
          child: const Text('Complete'),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}