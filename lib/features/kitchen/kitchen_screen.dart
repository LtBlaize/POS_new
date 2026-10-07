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
import '../../core/models/promo.dart';
import '../../core/providers/lan_orders_notifier.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/tables/table_provider.dart';
import '../../shared/widgets/app_colors.dart';
import '../../core/services/lan_client_service.dart';
import '../../../main.dart' show deviceRoleProvider, DeviceRole;
import '../../config/business_config.dart';
import '../../core/providers/order_provider.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/sync_queue_service.dart';
import '../../core/models/product_variant.dart';

// ── Supabase kitchen orders provider ──────────────────────────────────────────
//
// Used by owner role and as fallback when LAN is disconnected.
// Polls every 10 seconds and also exposes a manual refresh.

final _kitchenOrdersFromDbProvider =
    AsyncNotifierProvider<_KitchenDbNotifier, List<Order>>(
        _KitchenDbNotifier.new);

typedef RoundAdvance = Future<void> Function(String orderId, int round, String next);

class _KitchenDbNotifier extends AsyncNotifier<List<Order>> {
  @override
  Future<List<Order>> build() async {
    final online = ref.watch(isOnlineProvider);
    ref.watch(syncCompleteProvider);
    ref.watch(localOrdersRevisionProvider);

    final timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (ref.read(isOnlineProvider)) ref.invalidateSelf();
    });
    ref.onDispose(timer.cancel);

    return _fetch(online);
  }

  Future<List<Order>> _fetch(bool online) async {
    final businessId = ref.read(businessProvider)?.id;
    if (businessId == null || businessId.isEmpty) return [];
    final local = ref.read(localDbServiceProvider);

    if (online) {
      try {
        final rows = await Supabase.instance.client
            .from('orders')
            .select(
                '*, order_items(*, products(id, name, price, business_id, send_to_kitchen), product_variants(id, product_id, name, price_delta, cost_price, stock_quantity, is_active))')
            .eq('business_id', businessId)
            .inFilter('status', ['pending', 'preparing', 'ready'])
            .order('created_at', ascending: true);

        final remote = rows.map((row) => _parseDbOrder(row)).toList();

        final remoteIds = remote.map((o) => o.id).toSet();
        final unsynced = await local.getUnsyncedOrderIds();
        final localOnly = (await local.getActiveKitchenOrders(businessId))
            .where((o) => unsynced.contains(o.id) && !remoteIds.contains(o.id))
            .toList();

        final merged = <String, Order>{};
        for (final o in [...localOnly, ...remote]) {
          if (merged.containsKey(o.id)) {
            debugPrint('[Kitchen] DUPLICATE id ${o.id} #${o.orderNumber}');
          }
          merged[o.id] = o; // remote wins
        }
        return merged.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      } catch (e) {
        debugPrint('[Kitchen] Supabase fetch error, using local DB: $e');
      }
    }
    return local.getActiveKitchenOrders(businessId);
  }

  Future<void> advanceRound(String orderId, int round, String next) async {
    state = AsyncData((state.value ?? []).map((o) {
      if (o.id != orderId) return o;
      final items = [
        for (final i in o.items)
          (i.round == round && i.kitchenStatus != 'served')
              ? i.withKitchenStatus(next)
              : i,
      ];
      return o.copyWith(
        items: items,
        status: OrderStatusX.fromString(
            deriveOrderStatus(items.map((i) => i.kitchenStatus))),
      );
    }).toList());
    try {
      await ref.read(orderServiceProvider).setRoundStatus(
          orderId: orderId, round: round, status: next);
    } catch (e) {
      debugPrint('[Kitchen] Round status error: $e');
      ref.invalidateSelf();
    }
  }

  Order _parseDbOrder(Map<String, dynamic> m) {
    final rawItems = (m['order_items'] as List? ?? []).cast<Map<String, dynamic>>();

    final items = CartItem.groupOrderItemRows<Map<String, dynamic>>(
      rawItems,
      promoGroupId: (map) => map['promo_group_id'] as String?,
      isHeaderRow: (map) => map['product_id'] == null,
      buildItem: (map) {
        if (map['product_id'] == null) {
          return CartItem(
            product: Product.promo(
              id: 'promo_${map['promo_id']}',
              name: map['product_name'] as String? ?? 'Promo',
              price: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
            ),
            quantity: map['quantity'] as int? ?? 1,
            costAtSale: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
            notes: map['notes'] as String?,
            promoId: map['promo_id'] as String?,
            round: map['round'] as int? ?? 1,
            kitchenStatus: map['kitchen_status'] as String? ?? 'pending',            
          );
        }
        final product = map['products'] as Map<String, dynamic>? ?? {};
        return CartItem(
          product: Product(
            id: product['id'] as String? ?? '',
            businessId: product['business_id'] as String? ?? '',
            name: product['name'] as String? ?? map['product_name'] as String? ?? '',
            price: (product['price'] as num?)?.toDouble() ?? 0.0,
            sendToKitchen: product['send_to_kitchen'] as bool? ?? true,
          ),
          selectedVariant: map['product_variants'] != null
              ? ProductVariant.fromMap(
                  map['product_variants'] as Map<String, dynamic>)
              : null,          
          quantity: map['quantity'] as int? ?? 1,
          costAtSale: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
          notes: map['notes'] as String?,
          round: map['round'] as int? ?? 1,
          kitchenStatus: map['kitchen_status'] as String? ?? 'pending',
        );
      },
      buildComponent: (map) {
        final product = map['products'] as Map<String, dynamic>? ?? {};
        return PromoComponent(
          promoId: map['promo_id'] as String? ?? '',
          productId: map['product_id'] as String,
          productName:
              product['name'] as String? ?? map['product_name'] as String? ?? '',
          quantity: map['quantity'] as int? ?? 1,
          trackInventory: false,
          sendToKitchen: product['send_to_kitchen'] as bool? ?? true,
        );
      },
    );

    final kitchenItems = items.where((i) {
      if (i.isPromo) return i.promoComponents!.any((c) => c.sendToKitchen);
      return i.product.sendToKitchen;
    }).toList();

    return Order(
      id: m['id'] as String,
      businessId: m['business_id'] as String? ?? '',
      orderNumber: m['order_number'] as int? ?? 0,
      tableId: m['table_id'] as String?,
      orderType: OrderTypeX.fromString(m['order_type'] as String? ?? 'walk_in'),
      customerName: m['customer_name'] as String?,
      status: OrderStatusX.fromString(m['status'] as String),
      createdAt: DateTime.parse(m['created_at'] as String),
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
      items: kitchenItems,
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
      onAdvanceStatus: (orderId, round, next) =>
          ref.read(kitchenStateProvider.notifier).advanceRound(orderId, round, next),
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
      skipLoadingOnReload: true,
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
        onAdvanceStatus: (orderId, round, next) => ref
            .read(_kitchenOrdersFromDbProvider.notifier)
            .advanceRound(orderId, round, next),
      ),
    );
  }
}

// ── Shared kitchen body ────────────────────────────────────────────────────────

class _KitchenBody extends StatelessWidget {
  final List<Order> orders;
  final LanConnectionState connection;
  final bool isDbMode;
  final RoundAdvance onAdvanceStatus;

  const _KitchenBody({
    required this.orders,
    required this.connection,
    required this.onAdvanceStatus,
    this.isDbMode = false,
  });

  @override
  Widget build(BuildContext context) {
    OrderStatus effective(Order o) => o.items.isEmpty
        ? o.status
        : OrderStatusX.fromString(
            deriveOrderStatus(o.items.map((i) => i.kitchenStatus)));
    final pending   = orders.where((o) => effective(o) == OrderStatus.pending).toList();
    final preparing = orders.where((o) => effective(o) == OrderStatus.preparing).toList();
    final ready     = orders.where((o) => effective(o) == OrderStatus.ready).toList();

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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDbMode)
                      _DbModeIndicator()
                    else
                      _LanIndicator(state: connection),
                    const SizedBox(width: 12),
                    _KitchenStat(label: 'Pending',   count: pending.length,   color: AppColors.warning),
                    const SizedBox(width: 8),
                    _KitchenStat(label: 'Preparing', count: preparing.length, color: AppColors.info),
                    const SizedBox(width: 8),
                    _KitchenStat(label: 'Ready',     count: ready.length,     color: AppColors.success),
                  ],
                ),
              ],
            ),
          ),

          // Columns
          Expanded(
            child: orders.isEmpty
                ? _EmptyKitchen(isDbMode: isDbMode)
                                : LayoutBuilder(builder: (context, c) {
                    final row = Row(
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
                    );
                    if (c.maxWidth >= 720) return row;
                    // Narrow window: scroll sideways instead of overflowing.
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: 900, height: c.maxHeight, child: row),
                    );
                  }),
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
  final RoundAdvance onAdvanceStatus;

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
  final RoundAdvance onAdvanceStatus;

  const _KitchenOrderCard({
    super.key,
    required this.order,
    required this.onAdvanceStatus,
  });

  @override
  ConsumerState<_KitchenOrderCard> createState() => _KitchenOrderCardState();
}

class _KitchenOrderCardState extends ConsumerState<_KitchenOrderCard> {
  String? _busyRound;
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

  Future<void> _advance(int round, String next) async {
    setState(() => _busyRound = '$round');
    try {
      await widget.onAdvanceStatus(widget.order.id, round, next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRound = null);
    }
  }

  /// Who the food is for: "TABLE 1", "TABLE 1 · Juan", "TAKEOUT · Juan"...
  String _whereLabel() {
    final o = widget.order;
    final name = (o.customerName?.isNotEmpty ?? false) ? o.customerName! : null;
    final tableId = o.tableId;
    String base;
    if (tableId != null && tableId.isNotEmpty) {
      final n = ref.read(tableProvider).tableNameForUuid(tableId);
      base = n != null
          ? 'TABLE $n'
          : 'TABLE …${tableId.substring(tableId.length - 6)}';
    } else {
      base = switch (o.orderType) {
        OrderType.takeOut => 'TAKEOUT',
        OrderType.delivery => 'DELIVERY',
        OrderType.walkIn => 'WALK-IN',
      };
    }
    return name != null ? '$base · $name' : base;
  }

  String _formatAge(Duration d) {
    if (d.inMinutes < 1) return '< 1 min';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final age = DateTime.now().difference(order.createdAt);

    final rounds = <int, List<CartItem>>{};
    for (final i in order.items) {
      rounds.putIfAbsent(i.round, () => []).add(i);
    }
    final keys = rounds.keys.toList()..sort();

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
          Row(
            children: [
              Expanded(
                child: Text(_whereLabel(),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(_formatAge(age),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
          Text('Order #${order.orderNumber}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          if (keys.isEmpty)
            const Text('Loading items...',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary))
          else
            for (final r in keys)
              _roundSection(r, rounds[r]!, keys.length > 1),
        ],
      ),
    );
  }

  Widget _roundSection(int round, List<CartItem> lines, bool showHeader) {
    final status = lines.first.kitchenStatus;
    final served = status == 'served';
    final (label, color, next) = switch (status) {
      'pending' => ('Start Preparing', AppColors.warning, 'preparing'),
      'preparing' => ('Mark Ready', AppColors.info, 'ready'),
      'ready' => ('Mark Served', AppColors.success, 'served'),
      _ => ('', AppColors.textSecondary, ''),
    };
    final tag = switch (status) {
      'pending' => 'NEW',
      'preparing' => 'PREPARING',
      'ready' => 'READY',
      _ => 'SERVED',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: served ? Colors.transparent : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: served
                ? AppColors.divider
                : color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text('ROUND $round',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: served ? AppColors.textSecondary : color)),
                  const SizedBox(width: 8),
                  Text(tag,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: served
                              ? AppColors.textSecondary
                              : color.withValues(alpha: 0.8))),
                ],
              ),
            ),
          ..._linesFor(lines, served),
          if (!served) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: _busyRound == '$round'
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : ElevatedButton(
                      onPressed: () => _advance(round, next),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _linesFor(List<CartItem> items, bool served) =>
      items.expand<Widget>((item) {
        if (item.isPromo) {
          return item.promoComponents!
              .where((c) => c.sendToKitchen)
              .map((c) => _kitchenLine(
                    quantity: c.quantity * item.quantity,
                    name: c.variantName != null
                        ? '${c.productName} (${c.variantName})'
                        : c.productName,
                    subtitle: item.product.name,
                    served: served,
                  ));
        }
        return [
          _kitchenLine(
            quantity: item.quantity,
            name: item.product.name,
            subtitle: item.selectedVariant?.name,
            subtitleColor: AppColors.info,
            notes: item.notes,
            served: served,
          ),
        ];
      }).toList();

  Widget _kitchenLine({
    required int quantity,
    required String name,
    String? subtitle,
    Color subtitleColor = AppColors.warning,
    String? notes,
    bool served = false,
  }) {
    final grey = AppColors.textSecondary.withValues(alpha: 0.6);
    final strike = served ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: served ? 0.04 : 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text('$quantity',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: served ? grey : AppColors.primary)),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 12,
                        decoration: strike,
                        color: served ? grey : AppColors.textPrimary)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          decoration: strike,
                          color: served ? grey : subtitleColor)),
                if (notes != null && notes.isNotEmpty)
                  Text(notes,
                      style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          decoration: strike,
                          color: served ? grey : AppColors.warning)),
              ],
            ),
          ),
        ],
      ),
    );
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