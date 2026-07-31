// lib/features/kitchen/kitchen_screen.dart
//
// Kitchen display — owners see orders directly from Supabase.
// Dedicated kitchen devices (DeviceRole.kitchen) use the LAN stream.
// Falls back to Supabase polling when LAN is disconnected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/order.dart';
import '../../core/models/cart_item.dart';
import '../../core/models/product.dart';
import '../../core/providers/lan_orders_notifier.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/tables/table_provider.dart';
import '../../shared/widgets/app_colors.dart';
import '../../core/services/lan_client_service.dart';
import '../../core/services/lan_status_queue.dart';
import '../../../main.dart' show deviceRoleProvider, DeviceRole;
import '../../config/business_config.dart';

// ── Supabase kitchen orders provider ──────────────────────────────────────────
//
// Used by owner role and as fallback when LAN is disconnected.
// Polls every 10 seconds and also exposes a manual refresh.

final _kitchenOrdersFromDbProvider =
    AsyncNotifierProvider<_KitchenDbNotifier, List<Order>>(
        _KitchenDbNotifier.new);

class _KitchenDbNotifier extends AsyncNotifier<List<Order>> {
  Timer? _pollTimer;

  @override
  Future<List<Order>> build() async {
    // Cancel any previous timer when provider rebuilds
    _pollTimer?.cancel();
    // Start polling every 10 seconds.
    // AsyncNotifier does not have a `mounted` getter — we use onDispose
    // to cancel the timer instead, which is the correct Riverpod pattern.
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.invalidateSelf();
    });
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });
    return _fetch();
  }

  Future<List<Order>> _fetch() async {
    final businessId = ref.read(businessProvider)?.id;
    if (businessId == null || businessId.isEmpty) return [];

    final client = Supabase.instance.client;
    try {
      // Supabase returns PostgrestList (a List<dynamic> subtype).
      // Cast each element individually to avoid the List<dynamic> → List<Order> error.
      final rows = await client
          .from('orders')
          .select('*, order_items(*, products(id, name, price, business_id, send_to_kitchen))') 
          .eq('business_id', businessId)
          .inFilter('status', ['pending', 'preparing', 'ready'])
          .order('created_at', ascending: true);

      return rows
          .map((row) => _parseDbOrder(row))
          .toList();
    } catch (e) {
      debugPrint('[Kitchen] Supabase fetch error: $e');
      return state.value ?? [];
    }
  }

  Future<void> advanceStatus(String orderId, OrderStatus next) async {
    // Optimistic update
    final updated = (state.value ?? []).map((o) {
      return o.id == orderId ? o.copyWith(status: next) : o;
    }).toList();
    state = AsyncData(updated);

    try {
      await Supabase.instance.client
          .from('orders')
          .update({
            'status': next.value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
    } catch (e) {
      debugPrint('[Kitchen] Status update error: $e');
      // Revert on failure
      ref.invalidateSelf();
    }
  }

  Order _parseDbOrder(Map<String, dynamic> m) {
    final rawItems = m['order_items'] as List? ?? [];
    final items = rawItems.map((i) {
      final map = i as Map<String, dynamic>;
      final product = map['products'] as Map<String, dynamic>? ?? {};
      return CartItem(
        product: Product(
          id: product['id'] as String? ?? '',
          businessId: product['business_id'] as String? ?? '',
          name: product['name'] as String? ?? map['product_name'] as String? ?? '',
          price: (product['price'] as num?)?.toDouble() ?? 0.0,
          sendToKitchen: product['send_to_kitchen'] as bool? ?? true,
        ),
        quantity: map['quantity'] as int? ?? 1,
        costAtSale: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
        notes: map['notes'] as String?,
      );
    }).toList();
    final kitchenItems = items.where((i) => i.product.sendToKitchen).toList();

    return Order(
      id: m['id'] as String,
      businessId: m['business_id'] as String? ?? '',
      orderNumber: m['order_number'] as int? ?? 0,
      tableId: m['table_id'] as String?,
      status: OrderStatusX.fromString(m['status'] as String),
      createdAt: DateTime.parse(m['created_at'] as String),
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
      items: kitchenItems,  // 
    );
  }
}

// ── KitchenScreen ─────────────────────────────────────────────────────────────

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen>
    with WidgetsBindingObserver {

  // Whether this screen is using LAN mode (kitchen device) or DB mode (owner)
  bool get _isOwnerMode {
    final role = ref.read(deviceRoleProvider);
    if (role == DeviceRole.kitchen) return false;
    // Single-device mode: POS and kitchen run on the same device
    final kitchenMode = ref.read(businessConfigProvider)?.kitchenMode ?? 'single_device';
    return kitchenMode == 'single_device' || role == DeviceRole.pos;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isOwnerMode) _connect();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isOwnerMode) _connect();
  }

  void _connect() {
    final ip = ref.read(cashierIpProvider) ?? '';
    if (ip.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No POS IP configured. Go to Settings → LAN Connection.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    ref.read(cashierIpProvider.notifier).state = ip;
    final businessId = ref.read(businessProvider)?.id ?? '';
    ref.read(kitchenStateProvider.notifier).connect(businessId);
  }

  @override
  Widget build(BuildContext context) {
    // ── Owner / POS device: read directly from Supabase ───────────────────
    if (_isOwnerMode) {
      return _DbKitchenView();
    }

    // ── Kitchen device: use LAN stream, fall back to Supabase if offline ──
    final kitchenState = ref.watch(kitchenStateProvider);
    final isOffline = kitchenState.connection == LanConnectionState.disconnected;

    // If LAN is disconnected, fall back to DB view automatically
    if (isOffline) {
      return _DbKitchenView(showLanBanner: true);
    }

    return _KitchenBody(
      orders: kitchenState.orders,
      connection: kitchenState.connection,
      onAdvanceStatus: (orderId, next) async {
        // Optimistic update in the notifier (updates local UI immediately)
        ref.read(kitchenStateProvider.notifier).advanceStatus(orderId, next);
        // Route through the queue so failed patches are retried when POS
        // is temporarily unreachable — fixes issue #25 (silent drop).
        ref.read(lanStatusQueueProvider).enqueue(orderId, next.value);
      },
    );
  }
}

// ── DB-backed kitchen view (owner mode + LAN fallback) ────────────────────────

class _DbKitchenView extends ConsumerWidget {
  final bool showLanBanner;
  const _DbKitchenView({this.showLanBanner = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_kitchenOrdersFromDbProvider);

    return ordersAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error loading orders: $e')),
      ),
      data: (orders) => _KitchenBody(
        orders: orders,
        // Owner always shows as "connected" since they read from DB directly
        connection: showLanBanner
            ? LanConnectionState.disconnected
            : LanConnectionState.connected,
        isDbMode: true,
        onAdvanceStatus: (orderId, next) =>
            ref.read(_kitchenOrdersFromDbProvider.notifier).advanceStatus(orderId, next),
      ),
    );
  }
}

// ── Shared kitchen body ────────────────────────────────────────────────────────

class _KitchenBody extends StatelessWidget {
  final List<Order> orders;
  final LanConnectionState connection;
  final bool isDbMode;
  final Future<void> Function(String orderId, OrderStatus next) onAdvanceStatus;

  const _KitchenBody({
    required this.orders,
    required this.connection,
    required this.onAdvanceStatus,
    this.isDbMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final pending   = orders.where((o) => o.status == OrderStatus.pending).toList();
    final preparing = orders.where((o) => o.status == OrderStatus.preparing).toList();
    final ready     = orders.where((o) => o.status == OrderStatus.ready).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // Show LAN banner only for kitchen devices that are offline
          if (!isDbMode) _ConnectionBanner(state: connection),

          // Header
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
                // Show DB mode indicator for owner
                if (isDbMode)
                  _DbModeIndicator()
                else
                  _LanIndicator(state: connection),
                const SizedBox(width: 16),
                _KitchenStat(label: 'Pending',   count: pending.length,   color: AppColors.warning),
                const SizedBox(width: 12),
                _KitchenStat(label: 'Preparing', count: preparing.length, color: AppColors.info),
                const SizedBox(width: 12),
                _KitchenStat(label: 'Ready',     count: ready.length,     color: AppColors.success),
              ],
            ),
          ),

          // Columns
          Expanded(
            child: orders.isEmpty
                ? _EmptyKitchen(isDbMode: isDbMode)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _KitchenColumn(
                        title: 'Pending',
                        color: AppColors.warning,
                        orders: pending,
                        onAdvanceStatus: onAdvanceStatus,
                      ),
                      _KitchenColumn(
                        title: 'Preparing',
                        color: AppColors.info,
                        orders: preparing,
                        onAdvanceStatus: onAdvanceStatus,
                      ),
                      _KitchenColumn(
                        title: 'Ready',
                        color: AppColors.success,
                        orders: ready,
                        onAdvanceStatus: onAdvanceStatus,
                      ),
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
        ('Not connected to POS — showing orders from server instead', Colors.orange.shade700),
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

// ── DB mode indicator ─────────────────────────────────────────────────────────

class _DbModeIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(
              color: AppColors.success, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        const Text('Live',
            style: TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ],
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
      LanConnectionState.connected    => 'LAN live',
      LanConnectionState.polling      => 'Polling',
      LanConnectionState.connecting   => 'Connecting',
      LanConnectionState.disconnected => 'Offline',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
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
  final bool isDbMode;
  const _EmptyKitchen({this.isDbMode = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.kitchen_outlined,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha:0.25),
          ),
          const SizedBox(height: 12),
          const Text(
            'No active orders',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            isDbMode ? 'Refreshes every 10 seconds' : 'Waiting for orders from POS',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
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
  final Future<void> Function(String, OrderStatus) onAdvanceStatus;

  const _KitchenColumn({
    required this.title,
    required this.color,
    required this.orders,
    required this.onAdvanceStatus,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
            Expanded(
              child: orders.isEmpty
                  ? Center(
                      child: Text('No orders',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary.withValues(alpha:0.4))))
                  : ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _KitchenOrderCard(
                        key: ValueKey('${orders[i].id}-${orders[i].status}'),
                        order: orders[i],
                        onAdvanceStatus: onAdvanceStatus,
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
  final Future<void> Function(String, OrderStatus) onAdvanceStatus;

  const _KitchenOrderCard({
    super.key,
    required this.order,
    required this.onAdvanceStatus,
  });

  @override
  ConsumerState<_KitchenOrderCard> createState() => _KitchenOrderCardState();
}

class _KitchenOrderCardState extends ConsumerState<_KitchenOrderCard> {
  bool _loading = false;
  late Timer _ageTimer;

  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer.cancel();
    super.dispose();
  }

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
      await widget.onAdvanceStatus(widget.order.id, next);
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

  String? _resolveTableLabel() {
    final tableId = widget.order.tableId;
    if (tableId == null || tableId.isEmpty) return null;
    final tableNumber = ref.read(tableProvider).tableNameForUuid(tableId);
    if (tableNumber != null) return 'Table $tableNumber';
    return 'Table …${tableId.substring(tableId.length - 6)}';
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

    final age = DateTime.now().difference(order.createdAt);
    final isOld = age.inMinutes >= 10;
    final tableLabel = _resolveTableLabel();

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOld ? Colors.red.shade50 : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: isOld ? Colors.red.shade200 : AppColors.divider),
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

          if (tableLabel != null) ...[
            const SizedBox(height: 2),
            Text(tableLabel,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],

          const SizedBox(height: 8),

          if (order.items.isNotEmpty)
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha:0.1),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.product.name,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary)),
                            if (item.selectedVariant != null)
                              Text(item.selectedVariant!.name,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.info)),
                            if (item.notes != null && item.notes!.isNotEmpty)
                              Text(item.notes!,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.warning,
                                      fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
          else
            const Text('Loading items...',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),

          const SizedBox(height: 10),

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
        color: color.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text('$count',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: color.withValues(alpha:0.8), fontSize: 11)),
        ],
      ),
    );
  }
}