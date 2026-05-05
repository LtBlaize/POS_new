// features/reports/widgets/daily_tab.dart
// Daily Sales tab — KPI cards, hourly chart, payment breakdown, top products.

import 'package:flutter/material.dart';

import '../../../shared/widgets/app_colors.dart';
import '../reports_providers.dart';
import '../reports_screen.dart' show ReportLayout;
import 'report_widgets.dart';

class DailyTab extends StatelessWidget {
  final DailyReport report;
  final bool isRestaurant;
  final ReportLayout layout;

  const DailyTab({
    super.key,
    required this.report,
    required this.isRestaurant,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isRestaurant ? const Color(0xFF1A1A2E) : AppColors.primary;
    final isPhone = layout == ReportLayout.phone;
    final pad = isPhone ? 16.0 : 24.0;

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
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cached data banner ──────────────────────────────────────────
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

          // ── KPI row ─────────────────────────────────────────────────────
          isPhone
              ? _PhoneKpiGrid(report: report, accent: accent)
              : _WideKpiRow(report: report, accent: accent),
          SizedBox(height: isPhone ? 16 : 20),

          // ── Charts row ──────────────────────────────────────────────────
          isPhone
              ? Column(
                  children: [
                    ReportCard(
                      title: 'Sales by Hour',
                      icon: Icons.access_time_rounded,
                      child: HourlyChart(
                          sales: report.hourlySales, accent: accent),
                    ),
                    const SizedBox(height: 12),
                    ReportCard(
                      title: 'Payment Methods',
                      icon: Icons.credit_card_outlined,
                      child: report.isFromCache
                          ? _offlinePaymentNote()
                          : PaymentBreakdown(
                              data: report.revenueByPayment,
                              accent: accent),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: ReportCard(
                        title: 'Sales by Hour',
                        icon: Icons.access_time_rounded,
                        child: HourlyChart(
                            sales: report.hourlySales, accent: accent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ReportCard(
                        title: 'Payment Methods',
                        icon: Icons.credit_card_outlined,
                        child: report.isFromCache
                            ? _offlinePaymentNote()
                            : PaymentBreakdown(
                                data: report.revenueByPayment,
                                accent: accent),
                      ),
                    ),
                  ],
                ),

          SizedBox(height: isPhone ? 12 : 20),

          // ── Top products ─────────────────────────────────────────────────
          ReportCard(
            title: isRestaurant ? 'Top Dishes' : 'Top Products',
            icon: isRestaurant
                ? Icons.restaurant_menu_outlined
                : Icons.inventory_2_outlined,
            child: TopProductsTable(
              products: report.topProducts,
              accent: accent,
              isPhone: isPhone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlinePaymentNote() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          'Payment breakdown\nnot available offline',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI GRIDS
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneKpiGrid extends StatelessWidget {
  final DailyReport report;
  final Color accent;
  const _PhoneKpiGrid({required this.report, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            KpiCard(
              label: 'Total Revenue',
              value: '₱${fmtShort(report.totalRevenue)}',
              icon: Icons.payments_outlined,
              color: AppColors.success,
            ),
            const SizedBox(width: 10),
            KpiCard(
              label: 'Total Orders',
              value: '${report.totalOrders}',
              icon: Icons.receipt_long_outlined,
              color: accent,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            KpiCard(
              label: 'Avg Order Value',
              value: '₱${fmtShort(report.avgOrderValue)}',
              icon: Icons.trending_up_rounded,
              color: AppColors.info,
            ),
            const SizedBox(width: 10),
            KpiCard(
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
      ],
    );
  }
}

class _WideKpiRow extends StatelessWidget {
  final DailyReport report;
  final Color accent;
  const _WideKpiRow({required this.report, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        KpiCard(
          label: 'Total Revenue',
          value: '₱${fmtShort(report.totalRevenue)}',
          icon: Icons.payments_outlined,
          color: AppColors.success,
        ),
        const SizedBox(width: 12),
        KpiCard(
          label: 'Total Orders',
          value: '${report.totalOrders}',
          icon: Icons.receipt_long_outlined,
          color: accent,
        ),
        const SizedBox(width: 12),
        KpiCard(
          label: 'Avg Order Value',
          value: '₱${fmtShort(report.avgOrderValue)}',
          icon: Icons.trending_up_rounded,
          color: AppColors.info,
        ),
        const SizedBox(width: 12),
        KpiCard(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOURLY CHART
// ─────────────────────────────────────────────────────────────────────────────

class HourlyChart extends StatelessWidget {
  final List<HourlySale> sales;
  final Color accent;
  const HourlyChart({super.key, required this.sales, required this.accent});

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

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT BREAKDOWN
// ─────────────────────────────────────────────────────────────────────────────

class PaymentBreakdown extends StatelessWidget {
  final Map<String, double> data;
  final Color accent;
  const PaymentBreakdown(
      {super.key, required this.data, required this.accent});

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
          final pct =
              (e.value.value / total * 100).toStringAsFixed(1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
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

// ─────────────────────────────────────────────────────────────────────────────
// TOP PRODUCTS TABLE
// ─────────────────────────────────────────────────────────────────────────────

class TopProductsTable extends StatelessWidget {
  final List<TopProduct> products;
  final Color accent;
  final bool isPhone;

  const TopProductsTable({
    super.key,
    required this.products,
    required this.accent,
    required this.isPhone,
  });

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
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const SizedBox(width: 24),
              const Expanded(
                child: Text('PRODUCT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(
                width: 64,
                child: Text('QTY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5)),
              ),
              if (!isPhone)
                const SizedBox(
                  width: 100,
                  child: Text('REVENUE',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5)),
                ),
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
                          color: i == 0
                              ? accent
                              : AppColors.textSecondary)),
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
                  width: 64,
                  child: Text('${p.qty}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                if (!isPhone)
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