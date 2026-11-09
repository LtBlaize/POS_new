// lib/core/models/shift_report.dart
import 'package:intl/intl.dart';
import 'shift.dart';

class ReportRow {
  final String label;
  final String value;
  final bool bold;
  const ReportRow(this.label, this.value, {this.bold = false});
}

class ReportSection {
  final String title;
  final List<ReportRow> rows;
  const ReportSection(this.title, this.rows);
}

/// One source of truth for the shift report. Both the ESC/POS (thermal)
/// and PDF renderers read from this, so they always show the same numbers.
class ShiftReportData {
  final CashierShift shift;
  final String? businessName;
  final String? businessAddress;
  final int? orderCount;
  final int? itemsSold;
  final DateTime printedAt;

  ShiftReportData({
    required this.shift,
    this.businessName,
    this.businessAddress,
    this.orderCount,
    this.itemsSold,
    DateTime? printedAt,
  }) : printedAt = printedAt ?? DateTime.now();

  static final _num = NumberFormat('#,##0.00');
  static final _dt = DateFormat('MMM d, y h:mm a');

  /// "PHP" instead of the peso sign: thermal code pages and the built-in
  /// PDF fonts have no peso glyph.
  static String php(double v) => 'PHP ${_num.format(v)}';

  String get duration {
    final end = shift.closedAt ?? DateTime.now();
    final d = end.difference(shift.openedAt);
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  String get printedLabel => 'Printed ${_dt.format(printedAt)}';

  String? get notes {
    final n = shift.notes?.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  List<ReportRow> get header => [
    ReportRow('Cashier', shift.staffName),
    ReportRow('Opened', _dt.format(shift.openedAt)),
    if (shift.closedAt != null)
      ReportRow('Closed', _dt.format(shift.closedAt!)),
    ReportRow('Duration', duration),
  ];

  List<ReportSection> get sections {
    final s = shift;
    final diff = (s.overShort * 100).round() / 100; // kill float noise
    final result =
        diff == 0
            ? 'EXACT'
            : diff > 0
            ? 'OVER'
            : 'SHORT';
    final diffText =
        diff == 0 ? php(0) : '${diff > 0 ? '+' : '-'}${php(diff.abs())}';

    return [
      ReportSection('SALES', [
        ReportRow('Total Sales', php(s.totalSales), bold: true),
        ReportRow(' Cash', php(s.cashSales)),
        ReportRow(' GCash/Maya', php(s.gcashSales)),
        ReportRow(' Card/Other', php(s.otherSales)),
        if (orderCount != null) ReportRow('Orders', '$orderCount'),
        if (itemsSold != null) ReportRow('Items Sold', '$itemsSold'),
      ]),
      if (s.creditGiven > 0 || s.creditsPaid > 0)
        ReportSection('UTANG', [
          if (s.creditGiven > 0) ReportRow('Utang Given', php(s.creditGiven)),
          if (s.creditsPaid > 0)
            ReportRow('Utang Collected', php(s.creditsPaid)),
        ]),
      ReportSection('CASH DRAWER', [
        ReportRow('Opening Cash', php(s.openingCash)),
        ReportRow('+ Cash Sales', php(s.cashSales)),
        if (s.creditsPaid > 0)
          ReportRow('+ Utang Collected', php(s.creditsPaid)),
        if (s.expenses > 0) ReportRow('- Expenses', php(s.expenses)),
        ReportRow('Expected', php(s.expectedCash), bold: true),
        if (s.actualCashCount != null) ...[
          ReportRow('Actual Count', php(s.actualCashCount!), bold: true),
          ReportRow(result, diffText, bold: true),
        ],
      ]),
    ];
  }
}
