// test/core/services/shift_tally_test.dart
//
// Run: flutter test test/core/services/shift_tally_test.dart
//
// Tests the tally() inner function from ShiftService._computeShiftSummary().
// That function decides how each completed order is bucketed into:
//   totalSales / cashSales / gcashSales / otherSales
//
// It's not exported, so we reproduce the exact logic here as a pure function.
// If you change the bucketing in shift_service.dart, update tallyOrder() here too.

import 'package:flutter_test/flutter_test.dart';

// ── Reproduction of tally() from shift_service.dart ──────────────────────────

class ShiftTotals {
  double totalSales = 0;
  double cashSales = 0;
  double gcashSales = 0;
  double otherSales = 0;

  /// Mirrors the inner tally() closure in _computeShiftSummary().
  void tallyOrder(Map<String, dynamic> o) {
    final status = o['status'] as String? ?? '';
    final paidAt = o['paid_at'];
    final isPaid = status == 'completed' || paidAt != null;
    if (!isPaid) return;

    final amount = (o['total_amount'] as num).toDouble();
    final method = o['payment_method'] as String? ?? '';

    totalSales += amount;

    switch (method) {
      case 'cash':
        cashSales += amount;
      case 'gcash':
      case 'maya':
      case 'e_wallet':
        gcashSales += amount;
      default:
        otherSales += amount;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, dynamic> order({
  required double amount,
  required String method,
  String status = 'completed',
  String? paidAt,
}) =>
    {
      'total_amount': amount,
      'payment_method': method,
      'status': status,
      'paid_at': paidAt,
    };

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── isPaid gate ───────────────────────────────────────────────────────────

  group('isPaid gate', () {
    test('status=completed is counted', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 100, method: 'cash', status: 'completed'));
      expect(t.totalSales, 100.0);
    });

    test('status=pending is NOT counted', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 100, method: 'cash', status: 'pending'));
      expect(t.totalSales, 0.0);
    });

    test('status=cancelled is NOT counted', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 100, method: 'cash', status: 'cancelled'));
      expect(t.totalSales, 0.0);
    });

    test('non-completed but has paid_at IS counted', () {
      // An order might be in 'preparing' status but already have paid_at
      final t = ShiftTotals();
      t.tallyOrder(order(
        amount: 100,
        method: 'cash',
        status: 'preparing',
        paidAt: '2024-06-15T10:00:00Z',
      ));
      expect(t.totalSales, 100.0);
    });

    test('null payment_method defaults to empty string → goes to otherSales', () {
      final t = ShiftTotals();
      t.tallyOrder({
        'total_amount': 50.0,
        'payment_method': null,
        'status': 'completed',
        'paid_at': null,
      });
      expect(t.totalSales, 50.0);
      expect(t.otherSales, 50.0);
      expect(t.cashSales, 0.0);
    });
  });

  // ── Payment method bucketing ──────────────────────────────────────────────

  group('payment method bucketing', () {
    test('cash → cashSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 200, method: 'cash'));
      expect(t.cashSales, 200.0);
      expect(t.gcashSales, 0.0);
      expect(t.otherSales, 0.0);
    });

    test('gcash → gcashSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 150, method: 'gcash'));
      expect(t.gcashSales, 150.0);
      expect(t.cashSales, 0.0);
      expect(t.otherSales, 0.0);
    });

    test('maya → gcashSales (e-wallet bucket)', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 175, method: 'maya'));
      expect(t.gcashSales, 175.0);
      expect(t.cashSales, 0.0);
    });

    test('e_wallet → gcashSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 90, method: 'e_wallet'));
      expect(t.gcashSales, 90.0);
    });

    test('card → otherSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 500, method: 'card'));
      expect(t.otherSales, 500.0);
      expect(t.cashSales, 0.0);
      expect(t.gcashSales, 0.0);
    });

    test('unknown method → otherSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 120, method: 'bitcoin'));
      expect(t.otherSales, 120.0);
    });

    test('empty method string → otherSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 60, method: ''));
      expect(t.otherSales, 60.0);
    });
  });

  // ── totalSales accumulation ───────────────────────────────────────────────

  group('totalSales accumulation', () {
    test('all completed orders sum into totalSales regardless of method', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 100, method: 'cash'));
      t.tallyOrder(order(amount: 150, method: 'gcash'));
      t.tallyOrder(order(amount: 200, method: 'card'));
      expect(t.totalSales, 450.0);
    });

    test('pending orders are excluded from totalSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 100, method: 'cash'));
      t.tallyOrder(order(amount: 999, method: 'cash', status: 'pending'));
      expect(t.totalSales, 100.0);
    });

    test('mixed shift: cash + gcash + maya + card totals are correct', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 100, method: 'cash'));  // cash
      t.tallyOrder(order(amount: 200, method: 'gcash')); // gcash bucket
      t.tallyOrder(order(amount: 300, method: 'maya'));  // gcash bucket
      t.tallyOrder(order(amount: 400, method: 'card'));  // other
      t.tallyOrder(order(amount: 50, method: 'cash', status: 'cancelled')); // excluded

      expect(t.totalSales, 1000.0);
      expect(t.cashSales, 100.0);
      expect(t.gcashSales, 500.0); // 200 + 300
      expect(t.otherSales, 400.0);
    });

    test('totalSales == cashSales + gcashSales + otherSales', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 80, method: 'cash'));
      t.tallyOrder(order(amount: 120, method: 'gcash'));
      t.tallyOrder(order(amount: 50, method: 'card'));

      expect(
        t.cashSales + t.gcashSales + t.otherSales,
        closeTo(t.totalSales, 0.001),
      );
    });
  });

  // ── Edge cases ────────────────────────────────────────────────────────────

  group('edge cases', () {
    test('zero-amount order still tallied (free item)', () {
      final t = ShiftTotals();
      t.tallyOrder(order(amount: 0, method: 'cash'));
      expect(t.totalSales, 0.0);
      expect(t.cashSales, 0.0);
    });

    test('no orders → all totals are 0', () {
      final t = ShiftTotals();
      expect(t.totalSales, 0.0);
      expect(t.cashSales, 0.0);
      expect(t.gcashSales, 0.0);
      expect(t.otherSales, 0.0);
    });

    test('integer total_amount coerced to double', () {
      final t = ShiftTotals();
      t.tallyOrder({
        'total_amount': 100, // int, not double
        'payment_method': 'cash',
        'status': 'completed',
        'paid_at': null,
      });
      expect(t.totalSales, isA<double>());
      expect(t.totalSales, 100.0);
    });
  });
}