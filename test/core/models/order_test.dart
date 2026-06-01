// test/core/models/order_test.dart
//
// Run: flutter test test/core/models/order_test.dart
//
// Tests Order.fromMap deserialization, extension round-trips, and copyWith.

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_new/core/models/order.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Minimal valid order map (matches DB column names exactly).
Map<String, dynamic> baseMap() => {
      'id': 'order-abc',
      'business_id': 'biz-1',
      'table_id': null,
      'cashier_id': null,
      'order_number': 42,
      'order_type': 'walk_in',
      'status': 'pending',
      'subtotal': 200.0,
      'tax_amount': 24.0,
      'discount_amount': 10.0,
      'tip_amount': 5.0,
      'total_amount': 219.0,
      'payment_method': null,
      'amount_tendered': null,
      'change_amount': null,
      'reference_number': null,
      'notes': null,
      'paid_at': null,
      'created_at': '2024-06-15T08:30:00.000Z',
    };

Order makeOrder({
  double subtotal = 100,
  double taxAmount = 12,
  double discountAmount = 0,
  double tipAmount = 0,
  double totalAmount = 112,
  OrderStatus status = OrderStatus.pending,
  PaymentMethod? paymentMethod,
}) =>
    Order(
      id: 'o-1',
      businessId: 'biz-1',
      orderNumber: 1,
      subtotal: subtotal,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      tipAmount: tipAmount,
      totalAmount: totalAmount,
      status: status,
      paymentMethod: paymentMethod,
      createdAt: DateTime(2024, 6, 1),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── OrderType extension ───────────────────────────────────────────────────

  group('OrderTypeX', () {
    test('value strings are correct', () {
      expect(OrderType.walkIn.value, 'walk_in');
      expect(OrderType.takeOut.value, 'take_out');
      expect(OrderType.delivery.value, 'delivery');
    });

    test('fromString known values', () {
      expect(OrderTypeX.fromString('take_out'), OrderType.takeOut);
      expect(OrderTypeX.fromString('delivery'), OrderType.delivery);
      expect(OrderTypeX.fromString('walk_in'), OrderType.walkIn);
    });

    test('fromString unknown value defaults to walkIn', () {
      expect(OrderTypeX.fromString('unknown_type'), OrderType.walkIn);
      expect(OrderTypeX.fromString(''), OrderType.walkIn);
    });
  });

  // ── OrderStatus extension ─────────────────────────────────────────────────

  group('OrderStatusX', () {
    test('value strings are correct', () {
      expect(OrderStatus.pending.value, 'pending');
      expect(OrderStatus.preparing.value, 'preparing');
      expect(OrderStatus.ready.value, 'ready');
      expect(OrderStatus.completed.value, 'completed');
      expect(OrderStatus.cancelled.value, 'cancelled');
    });

    test('fromString all known values', () {
      expect(OrderStatusX.fromString('preparing'), OrderStatus.preparing);
      expect(OrderStatusX.fromString('ready'), OrderStatus.ready);
      expect(OrderStatusX.fromString('completed'), OrderStatus.completed);
      expect(OrderStatusX.fromString('cancelled'), OrderStatus.cancelled);
    });

    test('fromString unknown defaults to pending', () {
      expect(OrderStatusX.fromString('???'), OrderStatus.pending);
      expect(OrderStatusX.fromString(''), OrderStatus.pending);
    });
  });

  // ── PaymentMethod extension ───────────────────────────────────────────────

  group('PaymentMethodX', () {
    test('value strings are correct', () {
      expect(PaymentMethod.cash.value, 'cash');
      expect(PaymentMethod.card.value, 'card');
      expect(PaymentMethod.gcash.value, 'gcash');
      expect(PaymentMethod.maya.value, 'maya');
    });

    test('fromString all known values', () {
      expect(PaymentMethodX.fromString('card'), PaymentMethod.card);
      expect(PaymentMethodX.fromString('gcash'), PaymentMethod.gcash);
      expect(PaymentMethodX.fromString('maya'), PaymentMethod.maya);
      expect(PaymentMethodX.fromString('cash'), PaymentMethod.cash);
    });

    test('fromString unknown defaults to cash', () {
      expect(PaymentMethodX.fromString('bitcoin'), PaymentMethod.cash);
      expect(PaymentMethodX.fromString(''), PaymentMethod.cash);
    });
  });

  // ── Order.fromMap ─────────────────────────────────────────────────────────

  group('Order.fromMap', () {
    test('parses all required fields', () {
      final order = Order.fromMap(baseMap());

      expect(order.id, 'order-abc');
      expect(order.businessId, 'biz-1');
      expect(order.orderNumber, 42);
      expect(order.subtotal, 200.0);
      expect(order.taxAmount, 24.0);
      expect(order.discountAmount, 10.0);
      expect(order.tipAmount, 5.0);
      expect(order.totalAmount, 219.0);
      expect(order.status, OrderStatus.pending);
      expect(order.orderType, OrderType.walkIn);
    });

    test('null optional fields are null', () {
      final order = Order.fromMap(baseMap());
      expect(order.tableId, isNull);
      expect(order.cashierId, isNull);
      expect(order.paymentMethod, isNull);
      expect(order.amountTendered, isNull);
      expect(order.changeAmount, isNull);
      expect(order.referenceNumber, isNull);
      expect(order.paidAt, isNull);
    });

    test('parses payment_method when present', () {
      final map = baseMap()..['payment_method'] = 'gcash';
      final order = Order.fromMap(map);
      expect(order.paymentMethod, PaymentMethod.gcash);
    });

    test('parses paid_at when present', () {
      final map = baseMap()..['paid_at'] = '2024-06-15T10:00:00.000Z';
      final order = Order.fromMap(map);
      expect(order.paidAt, isNotNull);
      expect(order.paidAt!.year, 2024);
    });

    test('missing tip_amount in map defaults to 0.0', () {
      final map = baseMap()..remove('tip_amount');
      // tip_amount is num? → defaults to 0.0 in fromMap
      final order = Order.fromMap(map);
      expect(order.tipAmount, 0.0);
    });

    test('integer numeric fields are coerced to double', () {
      // Supabase sometimes returns int for numeric columns
      final map = baseMap()
        ..['subtotal'] = 200   // int
        ..['total_amount'] = 219; // int
      final order = Order.fromMap(map);
      expect(order.subtotal, isA<double>());
      expect(order.totalAmount, isA<double>());
    });

    test('order_type defaults to walkIn for unknown strings', () {
      final map = baseMap()..['order_type'] = 'catering';
      final order = Order.fromMap(map);
      expect(order.orderType, OrderType.walkIn);
    });

    test('status defaults to pending for unknown strings', () {
      final map = baseMap()..['status'] = 'limbo';
      final order = Order.fromMap(map);
      expect(order.status, OrderStatus.pending);
    });
  });

  // ── Order.copyWith ────────────────────────────────────────────────────────

  group('Order.copyWith', () {
    test('unchanged fields are preserved', () {
      final order = makeOrder(subtotal: 100, totalAmount: 112);
      final copy = order.copyWith(orderNumber: 99);
      expect(copy.subtotal, 100);
      expect(copy.totalAmount, 112);
      expect(copy.orderNumber, 99);
    });

    test('can update paymentMethod', () {
      final order = makeOrder();
      final paid = order.copyWith(paymentMethod: PaymentMethod.maya);
      expect(paid.paymentMethod, PaymentMethod.maya);
    });

    test('can update status', () {
      final order = makeOrder(status: OrderStatus.pending);
      final completed = order.copyWith(status: OrderStatus.completed);
      expect(completed.status, OrderStatus.completed);
    });

    test('copyWith does not mutate the original', () {
      final order = makeOrder(status: OrderStatus.pending);
      order.copyWith(status: OrderStatus.completed);
      expect(order.status, OrderStatus.pending);
    });

    test('can set discountAmount and it is preserved', () {
      final order = makeOrder();
      final discounted = order.copyWith(discountAmount: 20);
      expect(discounted.discountAmount, 20.0);
    });
  });

  // ── Order.total getter ────────────────────────────────────────────────────

  group('Order.total', () {
    test('total getter equals totalAmount field', () {
      final order = makeOrder(totalAmount: 219.0);
      expect(order.total, equals(order.totalAmount));
    });
  });
}