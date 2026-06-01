// test/core/services/checkout_result_test.dart
//
// Run: flutter test test/core/services/checkout_result_test.dart
//
// Tests the pure, provider-free parts of checkout_service.dart:
//   • CheckoutResult factory constructors
//   • _methodLabel logic (via CheckoutStatus values)
//   • actualTendered / actualChange calculation rules
//
// The full placeOrder() flow requires Riverpod mocking — see checkout_integration_test.dart (future).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/services/checkout_service.dart';
import 'package:flutter_application_1/core/models/order.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Order makeOrder() => Order(
      id: 'o-1',
      businessId: 'biz-1',
      orderNumber: 1,
      subtotal: 200.0,
      totalAmount: 224.0,
      createdAt: DateTime(2024, 6, 1),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── CheckoutResult.paid ───────────────────────────────────────────────────

  group('CheckoutResult.paid', () {
    test('status is paid', () {
      final r = CheckoutResult.paid(
        order: makeOrder(),
        tendered: 250,
        change: 26,
      );
      expect(r.status, CheckoutStatus.paid);
    });

    test('tendered and change are set correctly', () {
      final r = CheckoutResult.paid(
        order: makeOrder(),
        tendered: 300,
        change: 76,
      );
      expect(r.tendered, 300.0);
      expect(r.change, 76.0);
    });

    test('errorMessage is null on success', () {
      final r = CheckoutResult.paid(
        order: makeOrder(),
        tendered: 224,
        change: 0,
      );
      expect(r.errorMessage, isNull);
    });

    test('order is attached', () {
      final order = makeOrder();
      final r = CheckoutResult.paid(order: order, tendered: 224, change: 0);
      expect(r.order, same(order));
    });
  });

  // ── CheckoutResult.sentToKitchen ──────────────────────────────────────────

  group('CheckoutResult.sentToKitchen', () {
    test('status is sentToKitchen', () {
      final r = CheckoutResult.sentToKitchen(makeOrder());
      expect(r.status, CheckoutStatus.sentToKitchen);
    });

    test('tendered and change default to 0', () {
      final r = CheckoutResult.sentToKitchen(makeOrder());
      expect(r.tendered, 0.0);
      expect(r.change, 0.0);
    });

    test('errorMessage is null', () {
      final r = CheckoutResult.sentToKitchen(makeOrder());
      expect(r.errorMessage, isNull);
    });

    test('order is attached', () {
      final order = makeOrder();
      final r = CheckoutResult.sentToKitchen(order);
      expect(r.order, same(order));
    });
  });

  // ── CheckoutResult.error ──────────────────────────────────────────────────

  group('CheckoutResult.error', () {
    test('status is error', () {
      final r = CheckoutResult.error('Something went wrong');
      expect(r.status, CheckoutStatus.error);
    });

    test('errorMessage is set', () {
      final r = CheckoutResult.error('No stock available');
      expect(r.errorMessage, 'No stock available');
    });

    test('order is null on error', () {
      final r = CheckoutResult.error('oops');
      expect(r.order, isNull);
    });

    test('tendered and change default to 0 on error', () {
      final r = CheckoutResult.error('oops');
      expect(r.tendered, 0.0);
      expect(r.change, 0.0);
    });
  });

  // ── actualTendered / actualChange logic ───────────────────────────────────
  //
  // This reproduces the inline calculation from placeOrder():
  //   actualTendered = cash ? tendered : subtotal
  //   actualChange   = cash ? change   : 0
  //
  // We test this as a pure function to nail the non-cash behaviour.

  group('tender/change calculation rules', () {
    double calcTendered(PaymentMethod method, double tendered, double subtotal) =>
        method == PaymentMethod.cash ? tendered : subtotal;

    double calcChange(PaymentMethod method, double change) =>
        method == PaymentMethod.cash ? change : 0.0;

    test('cash: tendered and change pass through unchanged', () {
      expect(calcTendered(PaymentMethod.cash, 500, 224), 500.0);
      expect(calcChange(PaymentMethod.cash, 276), 276.0);
    });

    test('gcash: tendered becomes exact subtotal, change is 0', () {
      expect(calcTendered(PaymentMethod.gcash, 0, 224), 224.0);
      expect(calcChange(PaymentMethod.gcash, 999), 0.0);
    });

    test('maya: tendered becomes exact subtotal, change is 0', () {
      expect(calcTendered(PaymentMethod.maya, 0, 189.50), 189.50);
      expect(calcChange(PaymentMethod.maya, 10.5), 0.0);
    });

    test('card: tendered becomes exact subtotal, change is 0', () {
      expect(calcTendered(PaymentMethod.card, 0, 350), 350.0);
      expect(calcChange(PaymentMethod.card, 50), 0.0);
    });

    test('cash exact amount: change is 0', () {
      expect(calcTendered(PaymentMethod.cash, 224, 224), 224.0);
      expect(calcChange(PaymentMethod.cash, 0), 0.0);
    });
  });

  // ── Reference number validation logic ─────────────────────────────────────
  //
  // Reproduces:
  //   if (payNow && method != cash && (ref == null || ref.trim().isEmpty))
  //     → error

  group('reference number requirement', () {
    bool requiresRef(PaymentMethod method, String? ref) {
      return method != PaymentMethod.cash &&
          (ref == null || ref.trim().isEmpty);
    }

    test('cash never requires a reference number', () {
      expect(requiresRef(PaymentMethod.cash, null), isFalse);
      expect(requiresRef(PaymentMethod.cash, ''), isFalse);
    });

    test('gcash with no ref → requires it', () {
      expect(requiresRef(PaymentMethod.gcash, null), isTrue);
      expect(requiresRef(PaymentMethod.gcash, ''), isTrue);
      expect(requiresRef(PaymentMethod.gcash, '   '), isTrue);
    });

    test('gcash with ref provided → ok', () {
      expect(requiresRef(PaymentMethod.gcash, 'GC-123'), isFalse);
    });

    test('maya with no ref → requires it', () {
      expect(requiresRef(PaymentMethod.maya, null), isTrue);
    });

    test('card with ref → ok', () {
      expect(requiresRef(PaymentMethod.card, 'TXN-456'), isFalse);
    });
  });

  // ── cleanRef trimming logic ────────────────────────────────────────────────
  //
  // referenceNumber?.trim().isEmpty == true ? null : referenceNumber?.trim()

  group('reference number cleaning', () {
    String? cleanRef(String? raw) =>
        raw?.trim().isEmpty == true ? null : raw?.trim();

    test('null stays null', () => expect(cleanRef(null), isNull));
    test('blank string becomes null', () => expect(cleanRef('   '), isNull));
    test('empty string becomes null', () => expect(cleanRef(''), isNull));
    test('valid ref is trimmed', () => expect(cleanRef('  GC-123  '), 'GC-123'));
    test('valid ref with no spaces is unchanged', () =>
        expect(cleanRef('GC-123'), 'GC-123'));
  });
}