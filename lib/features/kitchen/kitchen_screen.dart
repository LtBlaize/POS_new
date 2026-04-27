// lib/features/kitchen/kitchen_screen.dart
//
// Kitchen display — reads from kitchenStateProvider (LAN) instead of
// Supabase. Works fully offline as long as both devices share a WiFi network.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/order.dart';
import '../../core/providers/lan_orders_notifier.dart';
import '../../features/auth/auth_provider.dart';
import '../../shared/widgets/app_colors.dart';

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final businessId = ref.read(businessProvider)?.id ?? '';
      ref.read(kitchenStateProvider.notifier).connect(businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final kitchenState = ref.watch(kitchenStateProvider);
    final orders = kitchenState.orders;

    final pending =
        orders.where((o) => o.status == OrderStatus.pending).toList();
    final preparing =
        orders.where((o) => o.status == OrderStatus.preparing).toList();
    final ready =
        orders.where((o) => o.status == OrderStatus.ready).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Connection banner ────────────────────────────────────────────
          _ConnectionBanner(state: kitchenState.connection),

          // ── Header ───────────────────────────────────────────────────────
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
            child: Row(
              children: [
                const Text(
                  'Kitchen Display',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                _LanIndicator(state: kitchenState.connection),
                const SizedBox(width: 16),
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

          // ── Columns ──────────────────────────────────────────────────────
          Expanded(
            child: orders.isEmpty
                ? _EmptyKitchen(state: kitchenState.connection)
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
      ),
    );
  }
}

// ── Connection banner ──────────────────────────────────────────────────────────

class _ConnectionBanner extends StatelessWidget {
  final LanConnectionState state;
  const _ConnectionBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (state) {
      LanConnectionState.disconnected =>
        ('Not connected to POS — check that both devices are on the same WiFi',
            Colors.red.shade700),
      LanConnectionState.connecting =>
        ('Connecting to POS...', Colors.orange.shade700),
      LanConnectionState.polling =>
        ('Live link degraded — polling every 5 s', Colors.orange.shade600),
      LanConnectionState.connected => ('', Colors.transparent),
    };

    if (state == LanConnectionState.connected) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── LAN indicator dot ──────────────────────────────────────────────────────────

class _LanIndicator extends StatelessWidget {
  final LanConnectionState state;
  const _LanIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      LanConnectionState.connected => AppColors.success,
      LanConnectionState.polling   => AppColors.warning,
      _                            => Colors.red,
    };
    final label = switch (state) {
      LanConnectionState.connected => 'LAN live',
      LanConnectionState.polling   => 'Polling',
      LanConnectionState.connecting => 'Connecting',
      LanConnectionState.disconnected => 'Offline',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyKitchen extends StatelessWidget {
  final LanConnectionState state;
  const _EmptyKitchen({required this.state});

  @override
  Widget build(BuildContext context) {
    final isOffline = state == LanConnectionState.disconnected;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOffline ? Icons.wifi_off_outlined : Icons.kitchen_outlined,
            size: 48,
            color: AppColors.textSecondary.withOpacity(0.25),
          ),
          const SizedBox(height: 12),
          Text(
            isOffline ? 'Cannot reach POS' : 'No active orders',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
          ),
          if (isOffline) ...[
            const SizedBox(height: 6),
            const Text(
              'Make sure both devices are on the same WiFi',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Column ─────────────────────────────────────────────────────────────────────

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
                border: Border(bottom: BorderSide(color: AppColors.divider)),
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
                              color: AppColors.textSecondary.withOpacity(0.4))))
                  : ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _KitchenOrderCard(
                        key: ValueKey('${orders[i].id}-${orders[i].status}'),
                        order: orders[i],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kitchen order card ─────────────────────────────────────────────────────────

class _KitchenOrderCard extends ConsumerStatefulWidget {
  final Order order;
  const _KitchenOrderCard({super.key, required this.order});

  @override
  ConsumerState<_KitchenOrderCard> createState() => _KitchenOrderCardState();
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
      // Optimistic update + LAN patch with automatic retry queue
      await ref
          .read(kitchenStateProvider.notifier)
          .advanceStatus(widget.order.id, next);
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
      OrderStatus.pending   => ('Start Preparing', AppColors.warning),
      OrderStatus.preparing => ('Mark Ready',      AppColors.info),
      OrderStatus.ready     => ('Mark Served',     AppColors.success),
      _                     => ('',                Colors.transparent),
    };

    // Age indicator — turns red after 10 minutes
    final age = DateTime.now().difference(order.createdAt);
    final isOld = age.inMinutes >= 10;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOld ? Colors.red.shade200 : AppColors.divider,
          width: isOld ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
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
              // Age chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOld
                      ? Colors.red.shade50
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: isOld
                          ? Colors.red.shade200
                          : AppColors.divider),
                ),
                child: Text(
                  _formatAge(age),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isOld
                          ? Colors.red.shade700
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),

          if (order.tableId != null && order.tableId!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Table ${order.tableId}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],

          const SizedBox(height: 8),

          // Items
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
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ))
          else
            const Text('Loading items...',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary)),

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
                          child:
                              CircularProgressIndicator(strokeWidth: 2)))
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
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
        ],
      ),
    );
  }

  String _formatAge(Duration d) {
    if (d.inMinutes < 1) return '< 1 min';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
}

// ── Stat pill ──────────────────────────────────────────────────────────────────

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
                  color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(width: 5),
          Text(label,
              style:
                  TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
        ],
      ),
    );
  }
}