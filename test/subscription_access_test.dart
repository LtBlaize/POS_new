import 'package:flutter_test/flutter_test.dart';
import 'package:fluxpoint/core/models/business.dart';
import 'package:fluxpoint/core/services/feature_manager.dart';
import 'package:fluxpoint/core/utils/trusted_clock.dart';

final _t0 = DateTime.utc(2026, 1, 1, 12);
final _end = DateTime.utc(2026, 1, 8, 12);

Business biz({
  String id = 'b1',
  DateTime? trialEnds,
  DateTime? subEnds,
  bool active = true,
}) => Business(
  id: id,
  name: 'Test',
  businessType: BusinessType.retail,
  subscriptionPlan: SubscriptionPlan.growth,
  isActive: active,
  createdAt: _t0,
  updatedAt: _t0,
  trialEndsAt: trialEnds,
  subscriptionExpiresAt: subEnds,
);

FeatureManager fm(Business? b) => FeatureManager(b, enforce: true);

void main() {
  tearDown(TrustedClock.reset);

  group('trial boundary', () {
    test('valid one second before expiry', () {
      TrustedClock.sync(_end.subtract(const Duration(seconds: 1)));
      expect(biz(trialEnds: _end).isOnActiveTrial, isTrue);
      expect(fm(biz(trialEnds: _end)).hasCoreAccess, isTrue);
    });

    test('expired at the expiry instant', () {
      TrustedClock.sync(_end);
      expect(biz(trialEnds: _end).isOnActiveTrial, isFalse);
      expect(fm(biz(trialEnds: _end)).hasCoreAccess, isFalse);
    });
  });

  group('precedence and payment states', () {
    test('active subscription beats an expired trial', () {
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      final b = biz(
        trialEnds: _end,
        subEnds: _end.add(const Duration(days: 30)),
      );
      expect(fm(b).hasCoreAccess, isTrue);
    });

    // Pending/failed payments never touch trial_ends_at or
    // subscription_expires_at, so the business stays in this state.
    test('expired trial with no confirmed subscription stays locked', () {
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      final f = fm(biz(trialEnds: _end));
      expect(f.hasCoreAccess, isFalse);
      for (final feature in [
        AppFeature.pos,
        AppFeature.orders,
        AppFeature.inventory,
        AppFeature.reports,
        AppFeature.credits,
      ]) {
        expect(f.hasFeature(feature), isFalse, reason: feature);
      }
    });

    test('confirmed activation restores access on the same instance type', () {
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      expect(fm(biz(trialEnds: _end)).hasCoreAccess, isFalse);
      final renewed = biz(
        trialEnds: _end,
        subEnds: _end.add(const Duration(days: 31)),
      );
      expect(fm(renewed).hasCoreAccess, isTrue);
    });

    test('suspended business is locked even with a live subscription', () {
      TrustedClock.sync(_t0);
      final b = biz(
        subEnds: _end,
        active: false,
      );
      expect(fm(b).hasCoreAccess, isFalse);
      expect(fm(b).canViewHistory, isFalse);
    });

    test('expired but active business can still view history', () {
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      expect(fm(biz(trialEnds: _end)).canViewHistory, isTrue);
    });
  });

  group('clock and tenant isolation', () {
    test('device clock far in the future does not expire a server-synced trial', () {
      // Device time is 2026-10 or later; the server says it is Jan 2026.
      TrustedClock.sync(_end.subtract(const Duration(hours: 1)));
      expect(biz(trialEnds: _end).isOnActiveTrial, isTrue);
    });

    test('offline floor stops a rolled-back device clock', () {
      final floor = DateTime.now().add(const Duration(days: 30));
      TrustedClock.setFloor(floor);
      expect(TrustedClock.now().isBefore(floor), isFalse);
    });

    test("one business's subscription does not unlock another", () {
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      final paid = biz(id: 'a', subEnds: _end.add(const Duration(days: 30)));
      final lapsed = biz(id: 'b', trialEnds: _end);
      expect(fm(paid).hasCoreAccess, isTrue);
      expect(fm(lapsed).hasCoreAccess, isFalse);
    });

    test('entitlement is business-level, so staff roles cannot bypass it', () {
      // FeatureManager takes only the Business; there is no role input.
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      expect(fm(biz(trialEnds: _end)).hasFeature(AppFeature.pos), isFalse);
    });

    test('enforcement off stays permissive for existing businesses', () {
      final off = FeatureManager(biz(trialEnds: _end), enforce: false);
      TrustedClock.sync(_end.add(const Duration(days: 1)));
      expect(off.hasCoreAccess, isTrue);
    });
  });
}