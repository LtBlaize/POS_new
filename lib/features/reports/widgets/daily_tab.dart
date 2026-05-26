// features/reports/widgets/daily_tab.dart
// Daily Sales tab — KPI cards, hourly chart, payment breakdown, top products.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_colors.dart';
import '../reports_providers.dart';
import '../reports_screen.dart';
import 'report_widgets.dart';

class DailyTab extends StatelessWidget {
  final DailyReport report;
  final bool isRestaurant;
  final ReportLayout layout;
  final bool isToday;
  final DateRange? dateRange;

  const DailyTab({
    super.key,
    required this.report,
    required this.isRestaurant,
    required this.layout,
    this.isToday = false,
    this.dateRange,
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
          // ── Range banner ─────────────────────────────────────────────────
          if (dateRange != null && !dateRange!.isSingleDay)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.info.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.date_range_outlined,
                      size: 14, color: AppColors.info),
                  const SizedBox(width: 8),
                  Text(
                    '${dateRange!.dayCount}-day summary: '
                    '${_fmtShortDate(dateRange!.start)} – '
                    '${_fmtShortDate(dateRange!.end)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.info,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // ── Live indicator ───────────────────────────────────────────────
          if (isToday && !report.isFromCache)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Live — refreshes every minute',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

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
          SizedBox(height: isPhone ? 12 : 16),

          // ── P&L summary card ─────────────────────────────────────────────
          if (report.totalRevenue > 0)
            _PLSummaryCard(report: report, accent: accent, isPhone: isPhone),

          SizedBox(height: isPhone ? 12 : 16),

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

          // ── Heatmap (range mode only) ────────────────────────────────────
          if (dateRange != null && !dateRange!.isSingleDay) ...[
            SalesHeatmap(dateRange: dateRange!, accent: accent),
            SizedBox(height: isPhone ? 12 : 20),
          ],

          // ── Tax & Discount summary ───────────────────────────────────────
          if (!report.isFromCache &&
              (report.totalTaxCollected > 0 || report.totalDiscount > 0))
            Padding(
              padding: EdgeInsets.only(bottom: isPhone ? 12 : 20),
              child: _TaxDiscountCard(
                  report: report, accent: accent, isPhone: isPhone),
            ),

          // ── Discount breakdown ───────────────────────────────────────────
          if (!report.isFromCache && report.totalDiscount > 0)
            Padding(
              padding: EdgeInsets.only(bottom: isPhone ? 12 : 20),
              child: _DiscountCard(
                  report: report, accent: accent, isPhone: isPhone),
            ),

          // ── Top products ─────────────────────────────────────────────────
          _ProductSection(
            report: report,
            accent: accent,
            isPhone: isPhone,
            isRestaurant: isRestaurant,
            dateRange: dateRange,
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

  static String _fmtShortDate(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
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
          label: 'Gross Profit',
          value: '₱${fmtShort(report.grossProfit)}',
          icon: Icons.trending_up_rounded,
          color: report.grossProfit >= 0 ? AppColors.success : AppColors.danger,
          sub: '${report.marginPct.toStringAsFixed(1)}% margin',
        ),
        const SizedBox(width: 12),
        KpiCard(
          label: 'COGS',
          value: '₱${fmtShort(report.totalCogs)}',
          icon: Icons.price_change_outlined,
          color: AppColors.info,
          sub: report.totalCogs == 0 ? 'No costs entered' : null,
          subColor: AppColors.textSecondary,
        ),
        const SizedBox(width: 12),
        KpiCard(
          label: 'Total Orders',
          value: '${report.totalOrders}',
          icon: Icons.receipt_long_outlined,
          color: accent,
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

// ─────────────────────────────────────────────────────────────────────────────
// DISCOUNT BREAKDOWN CARD
// ─────────────────────────────────────────────────────────────────────────────

class _DiscountCard extends StatelessWidget {
  final DailyReport report;
  final Color accent;
  final bool isPhone;
  const _DiscountCard(
      {required this.report, required this.accent, required this.isPhone});

  @override
  Widget build(BuildContext context) {
    final entries = report.discountByStaff.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = report.totalDiscount;

    return ReportCard(
      title: 'Discount Breakdown',
      icon: Icons.local_offer_outlined,
      child: Column(
        children: [
          // ── Summary row ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Discounts Given',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('₱${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning)),
              ],
            ),
          ),

          if (entries.isNotEmpty) ...[
            const SizedBox(height: 14),
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: const [
                  Expanded(
                    child: Text('CASHIER',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5)),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('AMOUNT',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5)),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text('SHARE',
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
            // ── Rows ───────────────────────────────────────────────────
            ...entries.map((e) {
              final pct = total > 0 ? e.value / total : 0.0;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: AppColors.divider, width: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text('₱${e.value.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning)),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                              '${(pct * 100).toStringAsFixed(1)}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LayoutBuilder(builder: (ctx, constraints) {
                      return Stack(children: [
                        Container(
                          height: 3,
                          width: constraints.maxWidth,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          height: 3,
                          width: constraints.maxWidth * pct,
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ]);
                    }),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAX & DISCOUNT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TaxDiscountCard extends StatelessWidget {
  final DailyReport report;
  final Color accent;
  final bool isPhone;
  const _TaxDiscountCard(
      {required this.report, required this.accent, required this.isPhone});

  @override
  Widget build(BuildContext context) {
    final taxRate = report.totalRevenue > 0
        ? (report.totalTaxCollected / report.totalRevenue * 100)
        : 0.0;
    final discountRate = report.totalRevenue > 0
        ? (report.totalDiscount /
                (report.totalRevenue + report.totalDiscount) *
                100)
        : 0.0;

    return ReportCard(
      title: 'Tax & Discounts',
      icon: Icons.receipt_outlined,
      child: isPhone
          ? Column(
              children: [
                _TaxRow(
                  label: 'Tax Collected',
                  value: report.totalTaxCollected,
                  sub: '${taxRate.toStringAsFixed(1)}% of revenue',
                  color: AppColors.info,
                  icon: Icons.account_balance_outlined,
                ),
                const SizedBox(height: 12),
                _TaxRow(
                  label: 'Discounts Given',
                  value: report.totalDiscount,
                  sub: '${discountRate.toStringAsFixed(1)}% of gross sales',
                  color: AppColors.warning,
                  icon: Icons.local_offer_outlined,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _TaxRow(
                    label: 'Tax Collected',
                    value: report.totalTaxCollected,
                    sub: '${taxRate.toStringAsFixed(1)}% of revenue',
                    color: AppColors.info,
                    icon: Icons.account_balance_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 48, color: AppColors.divider),
                const SizedBox(width: 12),
                Expanded(
                  child: _TaxRow(
                    label: 'Discounts Given',
                    value: report.totalDiscount,
                    sub: '${discountRate.toStringAsFixed(1)}% of gross sales',
                    color: AppColors.warning,
                    icon: Icons.local_offer_outlined,
                  ),
                ),
              ],
            ),
    );
  }
}

class _TaxRow extends StatelessWidget {
  final String label;
  final double value;
  final String sub;
  final Color color;
  final IconData icon;
  const _TaxRow({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('₱${value.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color)),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// P&L SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PLSummaryCard extends StatelessWidget {
  final DailyReport report;
  final Color accent;
  final bool isPhone;
  const _PLSummaryCard(
      {required this.report, required this.accent, required this.isPhone});

  @override
  Widget build(BuildContext context) {
    final hasCogsData = report.totalCogs > 0;

    return ReportCard(
      title: 'Profit & Loss',
      icon: Icons.account_balance_outlined,
      child: Column(
        children: [
          _PLRow(
            label: 'Gross Revenue',
            value: report.totalRevenue,
            isTotal: false,
            color: AppColors.textPrimary,
          ),
          _PLRow(
            label: 'Cost of Goods Sold',
            value: -report.totalCogs,
            isTotal: false,
            color: report.totalCogs > 0 ? AppColors.danger : AppColors.textSecondary,
            note: hasCogsData ? null : 'Add cost prices in Inventory',
          ),
          const Divider(height: 20, thickness: 0.5),
          _PLRow(
            label: 'Gross Profit',
            value: report.grossProfit,
            isTotal: true,
            color: report.grossProfit >= 0 ? AppColors.success : AppColors.danger,
          ),
          if (hasCogsData) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (report.marginPct >= 30
                        ? AppColors.success
                        : report.marginPct >= 10
                            ? AppColors.warning
                            : AppColors.danger)
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gross Margin',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500)),
                  Text(
                    '${report.marginPct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: report.marginPct >= 30
                          ? AppColors.success
                          : report.marginPct >= 10
                              ? AppColors.warning
                              : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!hasCogsData) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.divider.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set cost prices in Inventory to see COGS and gross profit.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PLRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isTotal;
  final Color color;
  final String? note;

  const _PLRow({
    required this.label,
    required this.value,
    required this.isTotal,
    required this.color,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final display = value < 0
        ? '−₱${(-value).toStringAsFixed(0)}'
        : '₱${value.toStringAsFixed(0)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: isTotal ? 14 : 13,
                        fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                        color: isTotal ? AppColors.textPrimary : AppColors.textSecondary)),
                if (note != null)
                  Text(note!,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(display,
              style: TextStyle(
                  fontSize: isTotal ? 15 : 13,
                  fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRODUCT SECTION (top sellers + slow movers, category filter, pagination)
// ─────────────────────────────────────────────────────────────────────────────

class _ProductSection extends ConsumerStatefulWidget {
  final DailyReport report;
  final Color accent;
  final bool isPhone;
  final bool isRestaurant;
  final DateRange? dateRange;

  const _ProductSection({
    required this.report,
    required this.accent,
    required this.isPhone,
    required this.isRestaurant,
    required this.dateRange,
  });

  @override
  ConsumerState<_ProductSection> createState() => _ProductSectionState();
}

class _ProductSectionState extends ConsumerState<_ProductSection> {
  String? _selectedCategory;
  int _topPageSize = 10;
  static const _pageStep = 10;

  @override
  Widget build(BuildContext context) {
    final threshold = ref.watch(slowMoverThresholdProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = widget.dateRange ??
        DateRange(start: today, end: today, preset: RangePreset.day);

    final slowAsync = ref.watch(
        slowMoversProvider((range: range, threshold: threshold)));

    // All categories from top products
    final allCategories = widget.report.topProducts
        .map((p) => p.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Filtered top products
    final filtered = _selectedCategory == null
        ? widget.report.topProducts
        : widget.report.topProducts
            .where((p) => p.category == _selectedCategory)
            .toList();

    final visible = filtered.take(_topPageSize).toList();
    final hasMore = filtered.length > _topPageSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Category filter chips ──────────────────────────────────────────
        if (allCategories.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CategoryChip(
                  label: 'All',
                  active: _selectedCategory == null,
                  onTap: () =>
                      setState(() => _selectedCategory = null),
                ),
                ...allCategories.map((c) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _CategoryChip(
                        label: c,
                        active: _selectedCategory == c,
                        onTap: () =>
                            setState(() => _selectedCategory = c),
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Top sellers card ───────────────────────────────────────────────
        ReportCard(
          title: widget.isRestaurant ? 'Top Dishes' : 'Top Products',
          icon: widget.isRestaurant
              ? Icons.restaurant_menu_outlined
              : Icons.inventory_2_outlined,
          child: Column(
            children: [
              TopProductsTable(
                products: visible,
                accent: widget.accent,
                isPhone: widget.isPhone,
              ),
              if (hasMore) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () =>
                      setState(() => _topPageSize += _pageStep),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color: AppColors.divider, width: 0.5)),
                    ),
                    child: Text(
                      'Show more (${filtered.length - _topPageSize} remaining)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.accent,
                      ),
                    ),
                  ),
                ),
              ],
              if (!hasMore && _topPageSize > _pageStep) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () =>
                      setState(() => _topPageSize = _pageStep),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color: AppColors.divider, width: 0.5)),
                    ),
                    child: Text(
                      'Show less',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Slow movers card ───────────────────────────────────────────────
        ReportCard(
          title: 'Slow Movers',
          icon: Icons.trending_down_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Threshold control
              Row(
                children: [
                  const Text('Threshold:',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  _ThresholdStepper(
                    value: threshold,
                    onChanged: (v) => ref
                        .read(slowMoverThresholdProvider.notifier)
                        .state = v,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '≤ $threshold unit${threshold == 1 ? '' : 's'} sold',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              slowAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Slow movers require an internet connection.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                data: (items) {
                  final filtered2 = _selectedCategory == null
                      ? items
                      : items
                          .where(
                              (p) => p.category == _selectedCategory)
                          .toList();
                  if (filtered2.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No slow movers for this period',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return TopProductsTable(
                    products: filtered2,
                    accent: AppColors.warning,
                    isPhone: widget.isPhone,
                    showRank: false,
                    emptyBarColor: AppColors.warning,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppColors.primary.withOpacity(0.4)
                : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color:
                active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ThresholdStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ThresholdStepper(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove,
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text('$value',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        _StepBtn(
          icon: Icons.add,
          onTap: value < 99 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(6),
          color: onTap == null ? AppColors.surface : Colors.white,
        ),
        child: Icon(icon,
            size: 14,
            color: onTap == null
                ? AppColors.textSecondary.withOpacity(0.3)
                : AppColors.textSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP PRODUCTS TABLE (reused for both top sellers and slow movers)
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// SALES HEATMAP (multi-day ranges only)
// ─────────────────────────────────────────────────────────────────────────────

class SalesHeatmap extends ConsumerWidget {
  final DateRange dateRange;
  final Color accent;

  const SalesHeatmap({
    super.key,
    required this.dateRange,
    required this.accent,
  });

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  // Show 6am–11pm (hours 6–23)
  static const _startHour = 6;
  static const _endHour = 23;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmapAsync = ref.watch(heatmapProvider(dateRange));

    return ReportCard(
      title: 'Sales Heatmap',
      icon: Icons.grid_view_rounded,
      child: heatmapAsync.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => const SizedBox(
          height: 60,
          child: Center(
            child: Text('Could not load heatmap',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ),
        data: (heatmap) {
          if (heatmap.maxAmount == 0) {
            return const SizedBox(
              height: 60,
              child: Center(
                child: Text('No data for this range',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            );
          }

          final hours = List.generate(
              _endHour - _startHour + 1, (i) => _startHour + i);

          // Build lookup: weekday → hour → cell
          final Map<int, Map<int, HeatmapCell>> lookup = {};
          for (final c in heatmap.cells) {
            lookup.putIfAbsent(c.weekday, () => <int, HeatmapCell>{})[c.hour] = c;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hour axis labels ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Row(
                  children: hours.map((h) {
                    final show = h % 3 == 0;
                    return Expanded(
                      child: Text(
                        show ? _hourLabel(h) : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textSecondary),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 4),

              // ── Grid rows ────────────────────────────────────────────
              ...List.generate(7, (wdIdx) {
                final wd = wdIdx + 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      // Day label
                      SizedBox(
                        width: 32,
                        child: Text(
                          _days[wdIdx],
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Cells
                      ...hours.map((h) {
                        final cell = lookup[wd]?[h];
                        final intensity = (heatmap.maxAmount > 0 && cell != null)
                            ? (cell.amount / heatmap.maxAmount).clamp(0.0, 1.0)
                            : 0.0;
                        return Expanded(
                          child: Tooltip(
                            message: cell != null && cell.amount > 0
                                ? '${_days[wdIdx]} ${_hourLabel(h)}\n'
                                  '₱${cell.amount.toStringAsFixed(0)}'
                                  ' · ${cell.orderCount} order${cell.orderCount == 1 ? '' : 's'}'
                                : '',
                            child: Container(
                              height: 20,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: intensity == 0
                                    ? AppColors.divider.withOpacity(0.5)
                                    : accent.withOpacity(
                                        0.12 + intensity * 0.85),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 10),

              // ── Legend ───────────────────────────────────────────────
              Row(
                children: [
                  const Text('Low',
                      style: TextStyle(
                          fontSize: 9, color: AppColors.textSecondary)),
                  const SizedBox(width: 6),
                  ...List.generate(5, (i) {
                    final intensity = (i + 1) / 5;
                    return Container(
                      width: 16,
                      height: 10,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12 + intensity * 0.85),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                  const SizedBox(width: 6),
                  const Text('High',
                      style: TextStyle(
                          fontSize: 9, color: AppColors.textSecondary)),
                ],
              ),
            ],
          );
        },
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
class TopProductsTable extends StatelessWidget {
  final List<TopProduct> products;
  final Color accent;
  final bool isPhone;
  final bool showRank;
  final Color? emptyBarColor;

  const TopProductsTable({
    super.key,
    required this.products,
    required this.accent,
    required this.isPhone,
    this.showRank = true,
    this.emptyBarColor,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No product data',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
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
              if (showRank) const SizedBox(width: 24),
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
              if (!isPhone) ...[
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
                const SizedBox(
                  width: 72,
                  child: Text('MARGIN',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5)),
                ),
              ],
            ],
          ),
        ),
        ...products.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final barRatio =
              maxQty > 0 ? p.qty / maxQty : 0.0;

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                if (showRank)
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
                      if (p.category.isNotEmpty)
                        Text(p.category,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary)),
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
                              color: (emptyBarColor ?? accent)
                                  .withOpacity(0.6),
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
                  child: Text(
                    p.qty == 0 ? '—' : '${p.qty}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: p.qty == 0
                            ? AppColors.textSecondary
                            : AppColors.textPrimary),
                  ),
                ),
                if (!isPhone) ...[
                  SizedBox(
                    width: 100,
                    child: Text(
                      p.revenue > 0
                          ? '₱${p.revenue.toStringAsFixed(0)}'
                          : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: p.revenue > 0
                              ? accent
                              : AppColors.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      p.cogs > 0
                          ? '${p.marginPct.toStringAsFixed(1)}%'
                          : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.cogs > 0
                            ? (p.marginPct >= 30
                                ? AppColors.success
                                : p.marginPct >= 10
                                    ? AppColors.warning
                                    : AppColors.danger)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}