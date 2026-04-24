// lib/features/reports/reports_screen.dart
//
// Offline-first reports:
//   Online  → fetch from Supabase, write-through to reports_cache in SQLite
//   Offline → read from reports_cache, show stale-data notice with last-synced time
//
// Everything below the provider is identical to your original UI — only the
// data-fetching provider and the error/offline state in the body changed.



import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/feature_manager.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../shared/widgets/app_colors.dart';
import '../../features/auth/auth_provider.dart';

// ── Data models (unchanged) ───────────────────────────────────────────────────

class _TopProduct {
  final String name;
  final int qty;
  final double revenue;
  const _TopProduct(this.name, this.qty, this.revenue);
}

class _HourlySale {
  final int hour;
  final double amount;
  const _HourlySale(this.hour, this.amount);
}

class _DailyReport {
  final double totalRevenue;
  final int totalOrders;
  final double avgOrderValue;
  final Map<String, double> revenueByPayment;
  final List<_TopProduct> topProducts;
  final List<_HourlySale> hourlySales;
  final int completedOrders;
  final int cancelledOrders;
  // NEW: metadata for offline display
  final bool isFromCache;
  final DateTime? cachedAt;

  const _DailyReport({
    required this.totalRevenue,
    required this.totalOrders,
    required this.avgOrderValue,
    required this.revenueByPayment,
    required this.topProducts,
    required this.hourlySales,
    required this.completedOrders,
    required this.cancelledOrders,
    this.isFromCache = false,
    this.cachedAt,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final _dailyReportProvider =
    FutureProvider.family<_DailyReport, DateTime>((ref, date) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) {
    return const _DailyReport(
      totalRevenue: 0, totalOrders: 0, avgOrderValue: 0,
      revenueByPayment: {}, topProducts: [], hourlySales: [],
      completedOrders: 0, cancelledOrders: 0,
    );
  }

  final businessId = profile!.businessId!;
  final isOnline = ref.read(isOnlineProvider);
  final local = ref.read(localDbServiceProvider);
  final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  if (!isOnline) {
    return _loadFromCache(local, businessId, dateKey);
  }

  // ── Online path ─────────────────────────────────────────────────────────────
  try {
    final client = ref.watch(supabaseClientProvider);

    final dayStart = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
    final dayEnd   = DateTime(date.year, date.month, date.day, 23, 59, 59).toUtc().toIso8601String();

    final rows = await client
        .from('orders')
        .select('*, order_items(product_name, quantity, subtotal)')
        .eq('business_id', businessId)
        .gte('created_at', dayStart)
        .lte('created_at', dayEnd)
        .order('created_at');

    final report = _buildReport(rows as List, fromCache: false);

    // Write-through to local cache
    await local.upsertReportDay(
      date: dateKey,
      businessId: businessId,
      totalSales: report.totalRevenue,
      orderCount: report.totalOrders,
      avgOrderValue: report.avgOrderValue,
      topProducts: report.topProducts
          .map((p) => {'name': p.name, 'qty': p.qty, 'revenue': p.revenue})
          .toList(),
    );

    return report;
  } catch (e) {
    // Network hiccup — fall back to cache silently
    return _loadFromCache(local, businessId, dateKey);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<_DailyReport> _loadFromCache(
  LocalDbService local,
  String businessId,
  String dateKey,
) async {
  final cached = await local.getReports(businessId,
      fromDate: dateKey, toDate: dateKey);

  if (cached.isEmpty) {
    return const _DailyReport(
      totalRevenue: 0, totalOrders: 0, avgOrderValue: 0,
      revenueByPayment: {}, topProducts: [], hourlySales: [],
      completedOrders: 0, cancelledOrders: 0,
      isFromCache: true,
    );
  }

  final row = cached.first;
  final syncedAt = row['synced_at'] != null
      ? DateTime.tryParse(row['synced_at'] as String)
      : null;

  final rawTopProducts =
      (row['top_products'] as List? ?? []).cast<Map<String, dynamic>>();

  return _DailyReport(
    totalRevenue: (row['total_sales'] as num?)?.toDouble() ?? 0,
    totalOrders: (row['order_count'] as int?) ?? 0,
    avgOrderValue: (row['avg_order_value'] as num?)?.toDouble() ?? 0,
    revenueByPayment: const {},   // not cached at row level — acceptable tradeoff
    topProducts: rawTopProducts
        .map((p) => _TopProduct(
              p['name'] as String,
              (p['qty'] as num).toInt(),
              (p['revenue'] as num).toDouble(),
            ))
        .toList(),
    hourlySales: List.generate(24, (h) => _HourlySale(h, 0)),
    completedOrders: (row['order_count'] as int?) ?? 0,
    cancelledOrders: 0,
    isFromCache: true,
    cachedAt: syncedAt,
  );
}

_DailyReport _buildReport(List orders, {required bool fromCache}) {
  double totalRevenue = 0;
  int completed = 0;
  int cancelled = 0;
  final Map<String, double> byPayment = {};
  final Map<String, _TopProduct> productMap = {};
  final Map<int, double> hourMap = {};

  for (final o in orders) {
    final row = o as Map<String, dynamic>;
    final status = row['status'] as String? ?? '';
    if (status == 'cancelled') { cancelled++; continue; }
    if (status == 'completed') completed++;

    final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
    final method = row['payment_method'] as String? ?? 'unknown';
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');

    if (row['paid_at'] != null) {
      totalRevenue += amount;
      byPayment[method] = (byPayment[method] ?? 0) + amount;
    }

    if (createdAt != null) {
      final h = createdAt.toLocal().hour;
      hourMap[h] = (hourMap[h] ?? 0) + amount;
    }

    final items = row['order_items'] as List? ?? [];
    for (final item in items) {
      final name = item['product_name'] as String? ?? 'Unknown';
      final qty  = item['quantity'] as int? ?? 0;
      final sub  = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
      final existing = productMap[name];
      productMap[name] = existing != null
          ? _TopProduct(name, existing.qty + qty, existing.revenue + sub)
          : _TopProduct(name, qty, sub);
    }
  }

  final topProducts = productMap.values.toList()
    ..sort((a, b) => b.qty.compareTo(a.qty));

  return _DailyReport(
    totalRevenue: totalRevenue,
    totalOrders: orders.length,
    avgOrderValue: completed > 0 ? totalRevenue / completed : 0,
    revenueByPayment: byPayment,
    topProducts: topProducts.take(5).toList(),
    hourlySales: List.generate(24, (h) => _HourlySale(h, hourMap[h] ?? 0)),
    completedOrders: completed,
    cancelledOrders: cancelled,
    isFromCache: fromCache,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerWidget {
  final FeatureManager featureManager;
  const ReportsScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(_selectedDateProvider);
    final reportAsync = ref.watch(_dailyReportProvider(selectedDate));
    final isOnline = ref.watch(isOnlineProvider);
    final isRestaurant = featureManager.hasFeature('kitchen') ||
        featureManager.hasFeature('tables');

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Offline notice ───────────────────────────────────────────────
          if (!isOnline)
            Container(
              width: double.infinity,
              color: const Color(0xFFB71C1C),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Offline — showing cached report data',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          // ── Header ──────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Daily Report',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isRestaurant
                                    ? const Color(0xFF1A1A2E)
                                    : AppColors.primary)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isRestaurant ? 'Restaurant' : 'Retail',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isRestaurant
                                  ? const Color(0xFF1A1A2E)
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(selectedDate),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                _DateNavButton(
                  icon: Icons.chevron_left,
                  onTap: () => ref.read(_selectedDateProvider.notifier).state =
                      selectedDate.subtract(const Duration(days: 1)),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      ref.read(_selectedDateProvider.notifier).state = picked;
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          _formatDateShort(selectedDate),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _DateNavButton(
                  icon: Icons.chevron_right,
                  onTap: selectedDate.isBefore(
                          DateTime.now().subtract(const Duration(days: 1)))
                      ? () => ref.read(_selectedDateProvider.notifier).state =
                          selectedDate.add(const Duration(days: 1))
                      : null,
                ),
                const SizedBox(width: 8),
                if (!_isToday(selectedDate))
                  TextButton(
                    onPressed: () {
                      final now = DateTime.now();
                      ref.read(_selectedDateProvider.notifier).state =
                          DateTime(now.year, now.month, now.day);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    child: const Text('Today',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: reportAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.danger)),
              ),
              data: (report) => _ReportBody(
                report: report,
                isRestaurant: isRestaurant,
                date: selectedDate,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  static String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _formatDateShort(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
}

// ── Report body ───────────────────────────────────────────────────────────────

class _ReportBody extends StatelessWidget {
  final _DailyReport report;
  final bool isRestaurant;
  final DateTime date;

  const _ReportBody({
    required this.report,
    required this.isRestaurant,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isRestaurant ? const Color(0xFF1A1A2E) : AppColors.primary;

    if (report.totalOrders == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 56,
                color: AppColors.textSecondary.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              'No orders for this day',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              report.isFromCache
                  ? 'No cached data available for this date'
                  : 'Select a different date to view reports',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stale-data notice (cache only) ─────────────────────────────
          if (report.isFromCache)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded,
                      size: 15, color: Color(0xFFF9A825)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      report.cachedAt != null
                          ? 'Cached data — last synced ${_timeAgo(report.cachedAt!)}'
                          : 'Showing cached data (offline)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6D4C00),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── KPI cards ──────────────────────────────────────────────────
          Row(
            children: [
              _KpiCard(
                label: 'Total Revenue',
                value: '₱${_fmt(report.totalRevenue)}',
                icon: Icons.payments_outlined,
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                label: 'Total Orders',
                value: '${report.totalOrders}',
                icon: Icons.receipt_long_outlined,
                color: accent,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                label: 'Avg Order Value',
                value: '₱${_fmt(report.avgOrderValue)}',
                icon: Icons.trending_up_rounded,
                color: AppColors.info,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                label: 'Completed',
                value: '${report.completedOrders}',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                sub: report.cancelledOrders > 0
                    ? '${report.cancelledOrders} cancelled'
                    : null,
                subColor: AppColors.danger,
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _Card(
                  title: 'Sales by Hour',
                  icon: Icons.access_time_rounded,
                  child: _HourlyChart(
                      sales: report.hourlySales, accent: accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _Card(
                  title: 'Payment Methods',
                  icon: Icons.credit_card_outlined,
                  child: report.isFromCache
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Payment breakdown\nnot available offline',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      : _PaymentBreakdown(
                          data: report.revenueByPayment,
                          accent: accent,
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _Card(
            title: isRestaurant ? 'Top Dishes' : 'Top Products',
            icon: isRestaurant
                ? Icons.restaurant_menu_outlined
                : Icons.inventory_2_outlined,
            child: _TopProductsTable(
              products: report.topProducts,
              accent: accent,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(2);
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── The widgets below are IDENTICAL to your originals ─────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  final Color? subColor;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
    this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!,
                  style: TextStyle(
                      fontSize: 11,
                      color: subColor ?? AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Card({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  final List<_HourlySale> sales;
  final Color accent;

  const _HourlyChart({required this.sales, required this.accent});

  @override
  Widget build(BuildContext context) {
    final max =
        sales.map((s) => s.amount).fold(0.0, (a, b) => a > b ? a : b);
    final visible =
        sales.where((s) => s.hour >= 6 && s.hour <= 23).toList();

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: visible.map((s) {
          final ratio = max > 0 ? s.amount / max : 0.0;
          final hasData = s.amount > 0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasData)
                    Text(
                      s.amount >= 1000
                          ? '${(s.amount / 1000).toStringAsFixed(1)}k'
                          : s.amount.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 7,
                          color: accent,
                          fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    height: (ratio * 110).clamp(2.0, 110.0),
                    decoration: BoxDecoration(
                      color: hasData
                          ? accent.withOpacity(0.8)
                          : AppColors.divider,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_hourLabel(s.hour),
                      style: const TextStyle(
                          fontSize: 8, color: AppColors.textSecondary)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _hourLabel(int h) {
    if (h == 0) return '12a';
    if (h < 12) return '${h}a';
    if (h == 12) return '12p';
    return '${h - 12}p';
  }
}

class _PaymentBreakdown extends StatelessWidget {
  final Map<String, double> data;
  final Color accent;

  const _PaymentBreakdown({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No payment data',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }

    final total = data.values.fold(0.0, (a, b) => a + b);
    final colors = [
      accent, AppColors.success, AppColors.info, AppColors.warning,
    ];
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: entries.asMap().entries.map((e) {
                final ratio = e.value.value / total;
                return Expanded(
                  flex: (ratio * 100).round(),
                  child: Container(color: colors[e.key % colors.length]),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...entries.asMap().entries.map((e) {
          final pct = (e.value.value / total * 100).toStringAsFixed(1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: colors[e.key % colors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_methodLabel(e.value.key),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary)),
                const Spacer(),
                Text('₱${e.value.value.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                Text('$pct%',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _methodLabel(String key) => switch (key) {
        'cash' => 'Cash',
        'card' => 'Card',
        'gcash' => 'GCash',
        'maya' => 'Maya',
        _ => key,
      };
}

class _TopProductsTable extends StatelessWidget {
  final List<_TopProduct> products;
  final Color accent;

  const _TopProductsTable(
      {required this.products, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No product data',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }

    final maxQty =
        products.map((p) => p.qty).fold(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(width: 24),
              Expanded(
                  child: Text('PRODUCT',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5))),
              SizedBox(
                  width: 80,
                  child: Text('QTY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5))),
              SizedBox(
                  width: 100,
                  child: Text('REVENUE',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5))),
            ],
          ),
        ),
        ...products.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final barRatio = maxQty > 0 ? p.qty / maxQty : 0.0;

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: i == 0 ? accent : AppColors.textSecondary)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      LayoutBuilder(builder: (ctx, constraints) {
                        return Stack(children: [
                          Container(
                            height: 4,
                            width: constraints.maxWidth,
                            decoration: BoxDecoration(
                              color: AppColors.divider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Container(
                            height: 4,
                            width: constraints.maxWidth * barRatio,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ]);
                      }),
                    ],
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text('${p.qty}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                SizedBox(
                  width: 100,
                  child: Text('₱${p.revenue.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _DateNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _DateNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
          color: onTap == null ? AppColors.surface : Colors.white,
        ),
        child: Icon(icon,
            size: 16,
            color: onTap == null
                ? AppColors.textSecondary.withOpacity(0.3)
                : AppColors.textSecondary),
      ),
    );
  }
}