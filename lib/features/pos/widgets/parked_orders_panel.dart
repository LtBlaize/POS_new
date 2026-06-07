// lib/features/pos/widgets/parked_orders_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/parked_order.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/parked_order_service.dart';
import '../../../shared/widgets/app_colors.dart';

class ParkedOrdersPanel extends ConsumerWidget {
  const ParkedOrdersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(parkedOrderProvider);

    return Container(
      width: 320,
      color: AppColors.surface,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.pause_circle_outline,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text('Parked Orders',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                if (state.orders.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${state.orders.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning)),
                  ),
              ],
            ),
          ),

          // ── List ────────────────────────────────────────────
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 36,
                                color: AppColors.textSecondary
                                    .withValues(alpha:0.25)),
                            const SizedBox(height: 8),
                            Text('No parked orders',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary
                                        .withValues(alpha:0.5))),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: state.orders.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final order = state.orders[index];
                          return _ParkedOrderCard(order: order);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ParkedOrderCard extends ConsumerWidget {
  final ParkedOrder order;
  const _ParkedOrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('₱${order.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.items
                .map((i) => '${i.quantity}× ${i.product.name}')
                .join(', '),
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _timeAgo(order.parkedAt),
            style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary.withValues(alpha:0.6)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _restore(context, ref),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Restore',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _delete(context, ref),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final currentCart = ref.read(cartProvider);
    if (currentCart.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace current cart?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: const Text(
              'Restoring this order will clear the current cart. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('Replace',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await ref.read(parkedOrderProvider.notifier).restoreToCart(order.id);
  }

  void _delete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove parked order?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('Delete "${order.label}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(parkedOrderProvider.notifier).deleteParked(order.id);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}