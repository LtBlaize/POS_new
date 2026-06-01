// test/core/models/cart_item_test.dart
//
// Run: flutter test test/core/models/cart_item_test.dart
//
// No mocks needed — CartItem is pure math + serialization.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/models/cart_item.dart';
import 'package:flutter_application_1/core/models/product.dart';
import 'package:flutter_application_1/core/models/product_variant.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Product makeProduct({
  String id = 'prod-1',
  double price = 100.0,
  double costPrice = 40.0,
  bool trackInventory = false,
}) =>
    Product(
      id: id,
      businessId: 'biz-1',
      name: 'Test Product',
      price: price,
      category: 'Food',
      trackInventory: trackInventory,
      sendToKitchen: false,
      costPrice: costPrice,
    );

ProductVariant makeVariant({
  String id = 'var-1',
  double priceDelta = 20.0,
  double costPrice = 60.0,
}) =>
    ProductVariant(
      id: id,
      productId: 'prod-1',
      name: 'Large',
      priceDelta: priceDelta,
      costPrice: costPrice,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── effectivePrice ─────────────────────────────────────────────────────────

  group('CartItem.effectivePrice', () {
    test('no variant → product base price', () {
      final item = CartItem(product: makeProduct(price: 100));
      expect(item.effectivePrice, equals(100.0));
    });

    test('with variant → base price + priceDelta', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        selectedVariant: makeVariant(priceDelta: 25),
      );
      expect(item.effectivePrice, equals(125.0));
    });

    test('variant with negative delta (discount variant)', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        selectedVariant: makeVariant(priceDelta: -10),
      );
      expect(item.effectivePrice, equals(90.0));
    });

    test('variant with zero delta → same as base price', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        selectedVariant: makeVariant(priceDelta: 0),
      );
      expect(item.effectivePrice, equals(100.0));
    });
  });

  // ── rawTotal ───────────────────────────────────────────────────────────────

  group('CartItem.rawTotal', () {
    test('qty 1 no variant', () {
      final item = CartItem(product: makeProduct(price: 50), quantity: 1);
      expect(item.rawTotal, equals(50.0));
    });

    test('qty 3 no variant', () {
      final item = CartItem(product: makeProduct(price: 50), quantity: 3);
      expect(item.rawTotal, equals(150.0));
    });

    test('qty 2 with variant priceDelta', () {
      final item = CartItem(
        product: makeProduct(price: 50),
        selectedVariant: makeVariant(priceDelta: 10),
        quantity: 2,
      );
      // effectivePrice = 60, qty = 2 → 120
      expect(item.rawTotal, equals(120.0));
    });
  });

  // ── discountValue ──────────────────────────────────────────────────────────

  group('CartItem.discountValue — fixed', () {
    test('fixed ₱20 discount', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        quantity: 1,
        discountAmount: 20,
        discountType: DiscountType.fixed,
      );
      expect(item.discountValue, equals(20.0));
    });

    test('fixed discount does NOT scale with quantity', () {
      // Fixed means a flat ₱20 off the line, regardless of qty
      final item = CartItem(
        product: makeProduct(price: 100),
        quantity: 3,
        discountAmount: 20,
        discountType: DiscountType.fixed,
      );
      expect(item.discountValue, equals(20.0));
    });

    test('fixed discount of 0 → no discount', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        discountAmount: 0,
        discountType: DiscountType.fixed,
      );
      expect(item.discountValue, equals(0.0));
    });
  });

  group('CartItem.discountValue — percentage', () {
    test('10% on ₱100 qty 1 → ₱10', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        quantity: 1,
        discountAmount: 10,
        discountType: DiscountType.percentage,
      );
      expect(item.discountValue, equals(10.0));
    });

    test('10% on ₱100 qty 3 → ₱30 (scales with rawTotal)', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        quantity: 3,
        discountAmount: 10,
        discountType: DiscountType.percentage,
      );
      // rawTotal = 300, 10% = 30
      expect(item.discountValue, equals(30.0));
    });

    test('100% discount → discountValue == rawTotal', () {
      final item = CartItem(
        product: makeProduct(price: 80),
        quantity: 2,
        discountAmount: 100,
        discountType: DiscountType.percentage,
      );
      expect(item.discountValue, equals(item.rawTotal));
    });

    test('0% → no discount', () {
      final item = CartItem(
        product: makeProduct(price: 80),
        discountAmount: 0,
        discountType: DiscountType.percentage,
      );
      expect(item.discountValue, equals(0.0));
    });
  });

  // ── total (clamped) ────────────────────────────────────────────────────────

  group('CartItem.total', () {
    test('no discount → total == rawTotal', () {
      final item = CartItem(product: makeProduct(price: 100), quantity: 2);
      expect(item.total, equals(200.0));
    });

    test('fixed discount reduces total', () {
      final item = CartItem(
        product: makeProduct(price: 100),
        quantity: 1,
        discountAmount: 30,
        discountType: DiscountType.fixed,
      );
      expect(item.total, equals(70.0));
    });

    test('percentage discount reduces total', () {
      final item = CartItem(
        product: makeProduct(price: 200),
        quantity: 1,
        discountAmount: 25, // 25%
        discountType: DiscountType.percentage,
      );
      expect(item.total, equals(150.0));
    });

    test('over-discount (fixed > rawTotal) clamps to 0, never negative', () {
      final item = CartItem(
        product: makeProduct(price: 50),
        quantity: 1,
        discountAmount: 999, // way more than the price
        discountType: DiscountType.fixed,
      );
      expect(item.total, equals(0.0));
    });

    test('total with variant price and percentage discount', () {
      // effectivePrice = 100 + 20 = 120, qty = 2, rawTotal = 240
      // 50% discount → discountValue = 120 → total = 120
      final item = CartItem(
        product: makeProduct(price: 100),
        selectedVariant: makeVariant(priceDelta: 20),
        quantity: 2,
        discountAmount: 50,
        discountType: DiscountType.percentage,
      );
      expect(item.total, equals(120.0));
    });
  });

  // ── costAtSale resolution ──────────────────────────────────────────────────

  group('CartItem.costAtSale', () {
    test('no variant → uses product.costPrice', () {
      final item = CartItem(product: makeProduct(costPrice: 40));
      expect(item.costAtSale, equals(40.0));
    });

    test('variant with costPrice > 0 → uses variant.costPrice', () {
      final item = CartItem(
        product: makeProduct(costPrice: 40),
        selectedVariant: makeVariant(costPrice: 65),
      );
      expect(item.costAtSale, equals(65.0));
    });

    test('variant with costPrice == 0 → falls back to product.costPrice', () {
      final item = CartItem(
        product: makeProduct(costPrice: 40),
        selectedVariant: makeVariant(costPrice: 0),
      );
      expect(item.costAtSale, equals(40.0));
    });

    test('explicit costAtSale constructor override is respected', () {
      final item = CartItem(
        product: makeProduct(costPrice: 40),
        costAtSale: 99,
      );
      expect(item.costAtSale, equals(99.0));
    });
  });

  // ── toParkedMap / fromParkedMap round-trip ─────────────────────────────────

  group('CartItem parked order serialization', () {
    test('round-trips a simple item with no variant', () {
      final original = CartItem(
        product: makeProduct(price: 150, costPrice: 55),
        quantity: 3,
        discountAmount: 10,
        discountType: DiscountType.fixed,
      );

      final map = original.toParkedMap();
      final restored = CartItem.fromParkedMap(map);

      expect(restored.product.id, equals(original.product.id));
      expect(restored.product.price, equals(original.product.price));
      expect(restored.quantity, equals(original.quantity));
      expect(restored.discountAmount, equals(original.discountAmount));
      expect(restored.discountType, equals(original.discountType));
      expect(restored.selectedVariant, isNull);
      expect(restored.costAtSale, equals(original.costAtSale));
    });

    test('round-trips an item WITH a variant', () {
      final original = CartItem(
        product: makeProduct(price: 100),
        selectedVariant: makeVariant(priceDelta: 30, costPrice: 70),
        quantity: 2,
        discountAmount: 5,
        discountType: DiscountType.percentage,
      );

      final map = original.toParkedMap();
      final restored = CartItem.fromParkedMap(map);

      expect(restored.selectedVariant, isNotNull);
      expect(restored.selectedVariant!.id, equals(original.selectedVariant!.id));
      expect(restored.selectedVariant!.priceDelta,
          equals(original.selectedVariant!.priceDelta));
      expect(restored.selectedVariant!.costPrice,
          equals(original.selectedVariant!.costPrice));
      expect(restored.discountType, equals(DiscountType.percentage));
      // Totals should survive the round-trip
      expect(restored.total, equals(original.total));
    });

    test('round-trip preserves computed total (no variant, fixed discount)', () {
      final original = CartItem(
        product: makeProduct(price: 200),
        quantity: 1,
        discountAmount: 50,
        discountType: DiscountType.fixed,
      );
      final restored = CartItem.fromParkedMap(original.toParkedMap());
      expect(restored.total, equals(150.0));
    });

    test('fromParkedMap with missing discount_type defaults to fixed', () {
      final map = CartItem(
        product: makeProduct(price: 80),
        quantity: 1,
      ).toParkedMap()..remove('discount_type');

      final restored = CartItem.fromParkedMap(map);
      expect(restored.discountType, equals(DiscountType.fixed));
    });

    test('fromParkedMap with null variant fields produces no variant', () {
      final map = CartItem(
        product: makeProduct(price: 80),
        quantity: 1,
      ).toParkedMap();
      expect(map['variant_id'], isNull);

      final restored = CartItem.fromParkedMap(map);
      expect(restored.selectedVariant, isNull);
    });
  });
}