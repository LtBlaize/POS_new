// lib/core/models/shift.dart

enum ShiftStatus { open, closed }

class CashierShift {
  final String id;
  final String businessId;
  final String staffId;
  final String staffName;
  final double openingCash;
  final DateTime openedAt;
  final ShiftStatus status;

  // Close-time fields
  final DateTime? closedAt;
  final double? actualCashCount;
  final String? notes;

  // Computed at close time (from orders during shift)
  final double totalSales;
  final double cashSales;
  final double gcashSales;
  final double otherSales;
  final double creditGiven; // utang added during shift
  final double expenses;    // placeholder, full tab later

  const CashierShift({
    required this.id,
    required this.businessId,
    required this.staffId,
    required this.staffName,
    required this.openingCash,
    required this.openedAt,
    required this.status,
    this.closedAt,
    this.actualCashCount,
    this.notes,
    this.totalSales = 0,
    this.cashSales = 0,
    this.gcashSales = 0,
    this.otherSales = 0,
    this.creditGiven = 0,
    this.expenses = 0,
  });

  // Expected cash = opening float + cash sales - expenses
  double get expectedCash => openingCash + cashSales - expenses;

  // Over/short = actual - expected (negative = short, positive = over)
  double get overShort =>
      actualCashCount != null ? actualCashCount! - expectedCash : 0;

  bool get isOver => overShort > 0;
  bool get isShort => overShort < 0;

  CashierShift copyWith({
    DateTime? closedAt,
    double? actualCashCount,
    String? notes,
    ShiftStatus? status,
    double? totalSales,
    double? cashSales,
    double? gcashSales,
    double? otherSales,
    double? creditGiven,
    double? expenses,
  }) =>
      CashierShift(
        id: id,
        businessId: businessId,
        staffId: staffId,
        staffName: staffName,
        openingCash: openingCash,
        openedAt: openedAt,
        status: status ?? this.status,
        closedAt: closedAt ?? this.closedAt,
        actualCashCount: actualCashCount ?? this.actualCashCount,
        notes: notes ?? this.notes,
        totalSales: totalSales ?? this.totalSales,
        cashSales: cashSales ?? this.cashSales,
        gcashSales: gcashSales ?? this.gcashSales,
        otherSales: otherSales ?? this.otherSales,
        creditGiven: creditGiven ?? this.creditGiven,
        expenses: expenses ?? this.expenses,
      );
}