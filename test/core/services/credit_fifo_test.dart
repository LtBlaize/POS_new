// test/core/services/credit_fifo_test.dart
//
// Run: flutter test test/core/services/credit_fifo_test.dart
//
// Tests the FIFO settlement algorithm from CreditService.recordPayment()
// in pure Dart — zero Supabase or SQLite dependencies.
//
// Why isolate this? The FIFO loop is the most money-critical logic in the
// whole app. A bug here means customers get credit balances wrong. We extract
// and test the pure math independently.

import 'package:flutter_test/flutter_test.dart';

// ── Extracted pure FIFO logic ─────────────────────────────────────────────────
//
// This mirrors the settlement loop inside CreditService.recordPayment().
// If you ever change that loop, update this model too.

class CreditTx {
  final String id;
  final double amountRemaining;
  CreditTx({required this.id, required this.amountRemaining});
}

class Settlement {
  final String creditTxId;
  final double amountApplied;
  final double newRemaining;
  final bool isSettled;
  Settlement({
    required this.creditTxId,
    required this.amountApplied,
    required this.newRemaining,
    required this.isSettled,
  });
}

class FifoResult {
  final List<Settlement> settlements;
  final double leftover;
  FifoResult({required this.settlements, required this.leftover});
}

/// Pure reproduction of the FIFO loop in CreditService.recordPayment().
FifoResult applyFifo(List<CreditTx> unsettled, double payment) {
  double remaining = payment;
  final settlements = <Settlement>[];

  for (final tx in unsettled) {
    if (remaining <= 0) break;

    final applied = remaining >= tx.amountRemaining ? tx.amountRemaining : remaining;
    final newRemaining = tx.amountRemaining - applied;
    remaining -= applied;

    settlements.add(Settlement(
      creditTxId: tx.id,
      amountApplied: applied,
      newRemaining: newRemaining,
      isSettled: newRemaining == 0,
    ));
  }

  return FifoResult(settlements: settlements, leftover: remaining);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Single credit, exact payment ──────────────────────────────────────────

  group('FIFO — single credit', () {
    test('exact payment fully settles the credit', () {
      final unsettled = [CreditTx(id: 'c1', amountRemaining: 200)];
      final result = applyFifo(unsettled, 200);

      expect(result.settlements.length, 1);
      expect(result.settlements[0].amountApplied, 200.0);
      expect(result.settlements[0].newRemaining, 0.0);
      expect(result.settlements[0].isSettled, isTrue);
      expect(result.leftover, 0.0);
    });

    test('partial payment leaves a remainder on the credit', () {
      final unsettled = [CreditTx(id: 'c1', amountRemaining: 200)];
      final result = applyFifo(unsettled, 150);

      expect(result.settlements[0].amountApplied, 150.0);
      expect(result.settlements[0].newRemaining, 50.0);
      expect(result.settlements[0].isSettled, isFalse);
      expect(result.leftover, 0.0);
    });

    test('overpayment leaves leftover, credit is fully settled', () {
      final unsettled = [CreditTx(id: 'c1', amountRemaining: 100)];
      final result = applyFifo(unsettled, 150);

      expect(result.settlements[0].amountApplied, 100.0);
      expect(result.settlements[0].isSettled, isTrue);
      expect(result.leftover, 50.0);
    });
  });

  // ── Multiple credits — FIFO order ─────────────────────────────────────────

  group('FIFO — multiple credits', () {
    test('payment covers first credit exactly, nothing applied to second', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 100),
        CreditTx(id: 'c2', amountRemaining: 200),
      ];
      final result = applyFifo(unsettled, 100);

      expect(result.settlements.length, 1); // only c1 was touched
      expect(result.settlements[0].creditTxId, 'c1');
      expect(result.settlements[0].isSettled, isTrue);
      expect(result.leftover, 0.0);
    });

    test('payment spills into second credit after fully settling first', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 100),
        CreditTx(id: 'c2', amountRemaining: 200),
      ];
      final result = applyFifo(unsettled, 250);

      expect(result.settlements.length, 2);

      final s1 = result.settlements[0];
      expect(s1.creditTxId, 'c1');
      expect(s1.amountApplied, 100.0);
      expect(s1.isSettled, isTrue);

      final s2 = result.settlements[1];
      expect(s2.creditTxId, 'c2');
      expect(s2.amountApplied, 150.0);
      expect(s2.newRemaining, 50.0);
      expect(s2.isSettled, isFalse);

      expect(result.leftover, 0.0);
    });

    test('payment covers all three credits with leftover', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 50),
        CreditTx(id: 'c2', amountRemaining: 75),
        CreditTx(id: 'c3', amountRemaining: 100),
      ];
      final result = applyFifo(unsettled, 300); // total owed = 225

      expect(result.settlements.length, 3);
      expect(result.settlements.every((s) => s.isSettled), isTrue);
      expect(result.leftover, 75.0); // 300 - 225 = 75
    });

    test('payment exactly settles all credits, zero leftover', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 50),
        CreditTx(id: 'c2', amountRemaining: 75),
        CreditTx(id: 'c3', amountRemaining: 100),
      ];
      final result = applyFifo(unsettled, 225);

      expect(result.settlements.every((s) => s.isSettled), isTrue);
      expect(result.leftover, 0.0);
    });

    test('tiny payment (₱1) only touches the oldest credit', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 500),
        CreditTx(id: 'c2', amountRemaining: 500),
      ];
      final result = applyFifo(unsettled, 1);

      expect(result.settlements.length, 1);
      expect(result.settlements[0].creditTxId, 'c1');
      expect(result.settlements[0].amountApplied, 1.0);
      expect(result.settlements[0].newRemaining, 499.0);
      expect(result.leftover, 0.0);
    });

    test('FIFO order is respected — oldest first', () {
      // Simulate: c1 is oldest, c3 is newest
      // A partial payment should go to c1 first
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 200), // oldest
        CreditTx(id: 'c2', amountRemaining: 200),
        CreditTx(id: 'c3', amountRemaining: 200), // newest
      ];
      final result = applyFifo(unsettled, 350);

      // c1 fully settled (200), c2 partially settled (150 applied)
      expect(result.settlements[0].creditTxId, 'c1');
      expect(result.settlements[0].isSettled, isTrue);
      expect(result.settlements[1].creditTxId, 'c2');
      expect(result.settlements[1].amountApplied, 150.0);
      expect(result.settlements[1].isSettled, isFalse);
      // c3 not touched
      expect(result.settlements.length, 2);
    });
  });

  // ── Edge cases ────────────────────────────────────────────────────────────

  group('FIFO — edge cases', () {
    test('empty unsettled list → no settlements, full leftover', () {
      final result = applyFifo([], 200);
      expect(result.settlements, isEmpty);
      expect(result.leftover, 200.0);
    });

    test('payment of 0 → no settlements, no leftover', () {
      final unsettled = [CreditTx(id: 'c1', amountRemaining: 100)];
      final result = applyFifo(unsettled, 0);
      expect(result.settlements, isEmpty);
      expect(result.leftover, 0.0);
    });

    test('sumOfApplied + leftover always equals original payment', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 80),
        CreditTx(id: 'c2', amountRemaining: 120),
      ];
      const payment = 250.0;
      final result = applyFifo(unsettled, payment);

      final totalApplied = result.settlements
          .fold(0.0, (sum, s) => sum + s.amountApplied);
      expect(totalApplied + result.leftover, closeTo(payment, 0.001));
    });

    test('amountApplied + newRemaining == original amountRemaining per credit', () {
      final unsettled = [
        CreditTx(id: 'c1', amountRemaining: 175),
        CreditTx(id: 'c2', amountRemaining: 90),
      ];
      final result = applyFifo(unsettled, 200);

      for (final s in result.settlements) {
        final original = unsettled.firstWhere((t) => t.id == s.creditTxId);
        expect(
          s.amountApplied + s.newRemaining,
          closeTo(original.amountRemaining, 0.001),
          reason: 'conservation failed for ${s.creditTxId}',
        );
      }
    });

    test('credit with amountRemaining of 0.01 (rounding scenario)', () {
      final unsettled = [CreditTx(id: 'c1', amountRemaining: 0.01)];
      final result = applyFifo(unsettled, 0.01);
      expect(result.settlements[0].isSettled, isTrue);
      expect(result.leftover, closeTo(0.0, 0.001));
    });
  });
}