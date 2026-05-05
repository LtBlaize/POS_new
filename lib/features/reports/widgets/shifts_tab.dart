// features/reports/widgets/shifts_tab.dart
// Shift Reports tab — day summary card + per-cashier expandable cards.

import 'package:flutter/material.dart';

import '../../../core/models/shift.dart';
import '../../../shared/widgets/app_colors.dart';
import '../reports_providers.dart';
import '../reports_screen.dart' show ReportLayout;
import 'report_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHIFTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class ShiftsTab extends StatefulWidget {
  final List<ShiftEntry> entries;
  final ReportLayout layout;

  const ShiftsTab({super.key, required this.entries, required this.layout});

  @override
  State<ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<ShiftsTab> {
  String? _expandedId;

  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);
  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final isPhone = widget.layout == ReportLayout.phone;
    final pad = isPhone ? 16.0 : 24.0;

    if (widget.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_outlined,
                size: 48,
                color: AppColors.textSecondary.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              'No shifts for this day',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Shifts appear here once a cashier opens one.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final summary = ShiftDaySummary.fromEntries(widget.entries);

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Day summary card ─────────────────────────────────────────────
          DaySummaryCard(
            summary: summary,
            isPhone: isPhone,
            accent: _accent,
            green: _green,
            blue: _blue,
            amber: _amber,
          ),
          SizedBox(height: isPhone ? 16 : 20),

          // ── Section label ────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'BY CASHIER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
          ),

          // ── Per-cashier shift cards ──────────────────────────────────────
          ...widget.entries.map((entry) {
            final isExpanded = _expandedId == entry.shift.id;
            return ShiftCard(
              entry: entry,
              isExpanded: isExpanded,
              isPhone: isPhone,
              onTap: () => setState(() {
                _expandedId = isExpanded ? null : entry.shift.id;
              }),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAY SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class DaySummaryCard extends StatelessWidget {
  final ShiftDaySummary summary;
  final bool isPhone;
  final Color accent;
  final Color green;
  final Color blue;
  final Color amber;

  const DaySummaryCard({
    super.key,
    required this.summary,
    required this.isPhone,
    required this.accent,
    required this.green,
    required this.blue,
    required this.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.summarize_outlined,
                    size: 15, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              const Text(
                'Day Total — All Shifts',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${summary.shiftCount} shift${summary.shiftCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '₱${fmtCurrency(summary.totalSales)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const Text(
            'Total Revenue',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SummaryChip(
                  label: 'Cash',
                  value: '₱${fmtShort(summary.cashSales)}',
                  color: green),
              SummaryChip(
                  label: 'GCash/Maya',
                  value: '₱${fmtShort(summary.gcashSales)}',
                  color: blue),
              SummaryChip(
                  label: 'Other',
                  value: '₱${fmtShort(summary.otherSales)}',
                  color: AppColors.textSecondary),
              SummaryChip(
                  label: 'Utang',
                  value: '₱${fmtShort(summary.creditGiven)}',
                  color: accent),
              SummaryChip(
                  label: 'Orders',
                  value: '${summary.totalOrders}',
                  color: AppColors.primary),
              SummaryChip(
                  label: 'Items',
                  value: '${summary.totalItems}',
                  color: AppColors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PER-CASHIER SHIFT CARD (expandable)
// ─────────────────────────────────────────────────────────────────────────────

class ShiftCard extends StatelessWidget {
  final ShiftEntry entry;
  final bool isExpanded;
  final bool isPhone;
  final VoidCallback onTap;

  const ShiftCard({
    super.key,
    required this.entry,
    required this.isExpanded,
    required this.isPhone,
    required this.onTap,
  });

  static const _green = Color(0xFF10B981);
  static const _amber = Color(0xFFF59E0B);
  static const _blue = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    final shift = entry.shift;
    final isOpen = shift.status == ShiftStatus.open;
    final statusColor = isOpen ? _amber : _green;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.divider,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(isExpanded ? 0.06 : 0.03),
            blurRadius: isExpanded ? 12 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Card header ──────────────────────────────────────────────
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            AppColors.primary.withOpacity(0.08),
                        child: Text(
                          shift.staffName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shift.staffName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _timeRange(shift),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isOpen ? 'Open' : 'Closed',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  // ── Quick stat row ─────────────────────────────────────
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        QuickStat(
                          label: 'Sales',
                          value: '₱${fmtShort(shift.totalSales)}',
                          color: _green,
                        ),
                        _vDivider(),
                        QuickStat(
                          label: 'Orders',
                          value: '${entry.orderCount}',
                          color: _blue,
                        ),
                        _vDivider(),
                        QuickStat(
                          label: 'Items',
                          value: '${entry.itemsSold}',
                          color: AppColors.textSecondary,
                        ),
                        _vDivider(),
                        QuickStat(
                          label: 'Duration',
                          value: _durationStr(entry.duration),
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded detail ──────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: isExpanded
                ? ShiftDetail(entry: entry, isPhone: isPhone)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: AppColors.divider,
      );

  String _timeRange(CashierShift s) {
    String fmt(DateTime dt) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final suffix = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:$m $suffix';
    }

    if (s.closedAt == null) return 'Opened ${fmt(s.openedAt)}';
    return '${fmt(s.openedAt)} → ${fmt(s.closedAt!)}';
  }

  String _durationStr(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPANDED SHIFT DETAIL
// ─────────────────────────────────────────────────────────────────────────────

class ShiftDetail extends StatelessWidget {
  final ShiftEntry entry;
  final bool isPhone;

  const ShiftDetail({super.key, required this.entry, required this.isPhone});

  static const _green = Color(0xFF10B981);
  static const _accent = Color(0xFFE94560);
  static const _blue = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    final shift = entry.shift;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sales breakdown ────────────────────────────────────────────
          const DetailSectionLabel('SALES BREAKDOWN'),
          const SizedBox(height: 10),
          isPhone
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: DetailCell(
                                label: 'Total',
                                value: '₱${fmtCurrency(shift.totalSales)}',
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: DetailCell(
                                label: 'Cash',
                                value: '₱${fmtCurrency(shift.cashSales)}',
                                color: _green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: DetailCell(
                                label: 'GCash/Maya',
                                value:
                                    '₱${fmtCurrency(shift.gcashSales)}',
                                color: _blue)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: DetailCell(
                                label: 'Utang',
                                value:
                                    '₱${fmtCurrency(shift.creditGiven)}',
                                color: _accent)),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                        child: DetailCell(
                            label: 'Total',
                            value: '₱${fmtCurrency(shift.totalSales)}',
                            color: AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: DetailCell(
                            label: 'Cash',
                            value: '₱${fmtCurrency(shift.cashSales)}',
                            color: _green)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: DetailCell(
                            label: 'GCash/Maya',
                            value: '₱${fmtCurrency(shift.gcashSales)}',
                            color: _blue)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: DetailCell(
                            label: 'Utang Given',
                            value:
                                '₱${fmtCurrency(shift.creditGiven)}',
                            color: _accent)),
                  ],
                ),

          const SizedBox(height: 16),

          // ── Transactions ───────────────────────────────────────────────
          const DetailSectionLabel('TRANSACTIONS'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: DetailCell(
                      label: 'Orders',
                      value: '${entry.orderCount}',
                      color: _blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: DetailCell(
                      label: 'Items Sold',
                      value: '${entry.itemsSold}',
                      color: _green)),
              const SizedBox(width: 8),
              Expanded(
                  child: DetailCell(
                      label: 'Avg / Order',
                      value: entry.orderCount > 0
                          ? '₱${fmtCurrency(entry.avgOrderValue)}'
                          : '—',
                      color: AppColors.textSecondary)),
            ],
          ),

          // ── Cash reconciliation ────────────────────────────────────────
          if (shift.closedAt != null) ...[
            const SizedBox(height: 16),
            const DetailSectionLabel('CASH RECONCILIATION'),
            const SizedBox(height: 10),
            CashReconcile(shift: shift),
          ],

          // ── Shift timing ───────────────────────────────────────────────
          const SizedBox(height: 16),
          const DetailSectionLabel('TIMING'),
          const SizedBox(height: 10),
          TimingRow(entry: entry),

          // ── Notes ──────────────────────────────────────────────────────
          if (shift.notes != null && shift.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const DetailSectionLabel('NOTES'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                shift.notes!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CASH RECONCILE BLOCK
// ─────────────────────────────────────────────────────────────────────────────

class CashReconcile extends StatelessWidget {
  final CashierShift shift;
  const CashReconcile({super.key, required this.shift});

  @override
  Widget build(BuildContext context) {
    final overShort = shift.overShort;
    final isExact = overShort == 0;
    final isOver = overShort > 0;
    final diffColor = isExact
        ? const Color(0xFF10B981)
        : isOver
            ? const Color(0xFF3B82F6)
            : const Color(0xFFE94560);
    final diffLabel = isExact
        ? 'Exact ✓'
        : isOver
            ? 'Over ▲'
            : 'Short ▼';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          ReconRow(
              label: 'Opening Cash',
              value: '₱${fmtCurrency(shift.openingCash)}',
              color: AppColors.textPrimary),
          ReconRow(
              label: '+ Cash Sales',
              value: '₱${fmtCurrency(shift.cashSales)}',
              color: const Color(0xFF10B981)),
          if (shift.expenses > 0)
            ReconRow(
                label: '− Expenses',
                value: '₱${fmtCurrency(shift.expenses)}',
                color: const Color(0xFFE94560)),
          const Divider(height: 14),
          ReconRow(
              label: 'Expected',
              value: '₱${fmtCurrency(shift.expectedCash)}',
              color: AppColors.textPrimary,
              bold: true),
          if (shift.actualCashCount != null) ...[
            ReconRow(
                label: 'Actual Count',
                value: '₱${fmtCurrency(shift.actualCashCount!)}',
                color: AppColors.textPrimary,
                bold: true),
            const Divider(height: 14),
            ReconRow(
                label: diffLabel,
                value:
                    '${isOver ? '+' : ''}₱${fmtCurrency(overShort.abs())}',
                color: diffColor,
                bold: true),
          ],
        ],
      ),
    );
  }
}

class ReconRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const ReconRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color:
                    bold ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              )),
          Text(value,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMING ROW
// ─────────────────────────────────────────────────────────────────────────────

class TimingRow extends StatelessWidget {
  final ShiftEntry entry;
  const TimingRow({super.key, required this.entry});

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final shift = entry.shift;
    final dur = entry.duration;
    final h = dur.inHours;
    final m = dur.inMinutes.remainder(60);

    return Row(
      children: [
        Expanded(
          child: DetailCell(
            label: 'Opened',
            value: _fmt(shift.openedAt),
            color: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: shift.closedAt != null
              ? DetailCell(
                  label: 'Closed',
                  value: _fmt(shift.closedAt!),
                  color: const Color(0xFFE94560),
                )
              : const DetailCell(
                  label: 'Status',
                  value: 'Still Open',
                  color: Color(0xFFF59E0B),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DetailCell(
            label: 'Duration',
            value: h == 0 ? '${m}m' : '${h}h ${m}m',
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}