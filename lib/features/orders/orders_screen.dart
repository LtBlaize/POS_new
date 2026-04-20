// lib/features/orders/orders_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/order_provider.dart';
import '../../core/models/order.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(orderProvider);
    final notifier = ref.read(orderProvider.notifier);

    Color statusColor(String status) => switch (status) {
          'pending' => Colors.orange,
          'preparing' => Colors.blue,
          'ready' => Colors.green,
          _ => Colors.grey,
        };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: orders.isEmpty
          ? const Center(child: Text('No orders yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(order.id,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const Spacer(),
                            Chip(
                              label: Text(order.status.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              backgroundColor: statusColor(order.status),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...order.items.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Text('${item.quantity}×  ${item.product.name}'),
                                  const Spacer(),
                                  Text('₱${item.total.toStringAsFixed(0)}'),
                                ],
                              ),
                            )),
                        const Divider(),
                        Row(
                          children: [
                            Text('Total: ₱${order.total.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            _StatusActions(order: order, notifier: notifier),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _StatusActions extends StatelessWidget {
  final Order order;
  final OrderNotifier notifier;

  const _StatusActions({required this.order, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return switch (order.status) {
      'pending' => ElevatedButton(
          onPressed: () => notifier.updateStatus(order.id, 'preparing'),
          child: const Text('Accept'),
        ),
      'preparing' => ElevatedButton(
          onPressed: () => notifier.updateStatus(order.id, 'ready'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Mark Ready'),
        ),
      'ready' => ElevatedButton(
          onPressed: () => notifier.removeOrder(order.id),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
          child: const Text('Complete'),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}