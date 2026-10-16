// lib/core/services/admin_subscription_service.dart
//
// Phase 7. Thin wrapper over the admin-subscription-action Edge Function.
// supabase_flutter's FunctionsClient automatically attaches the current
// session's JWT as the Authorization header — no manual header wiring
// needed, unlike a raw fetch.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminActionException implements Exception {
  final String message;
  AdminActionException(this.message);
  @override
  String toString() => message;
}

/// One limit that stops a downgrade, e.g. staff: 7 active, 2 allowed.
class DowngradeBlocker {
  final String limit; // staff | promos | tables | rooms | open_orders
  final int current;
  final int allowed;
  final int mustRemove;
  const DowngradeBlocker({
    required this.limit,
    required this.current,
    required this.allowed,
    required this.mustRemove,
  });

  factory DowngradeBlocker.fromMap(Map<String, dynamic> m) => DowngradeBlocker(
    limit: m['limit'] as String,
    current: (m['current'] as num).toInt(),
    allowed: (m['allowed'] as num).toInt(),
    mustRemove: (m['must_remove'] as num).toInt(),
  );

  /// Plain-language instruction you can send to the client.
  String get instruction => switch (limit) {
    'staff' =>
      'Deactivate $mustRemove staff account${mustRemove == 1 ? '' : 's'} '
          '(you have $current, the new plan allows $allowed).',
    'promos' =>
      'Deactivate $mustRemove promo${mustRemove == 1 ? '' : 's'} '
          '(you have $current active, the new plan allows $allowed).',
    'tables' =>
      'Remove $mustRemove table${mustRemove == 1 ? '' : 's'} '
          '(you have $current, the new plan allows $allowed).',
    'rooms' =>
      'Remove $mustRemove room${mustRemove == 1 ? '' : 's'} '
          '(you have $current, the new plan allows $allowed).',
    'open_orders' =>
      'Settle or cancel the $current open unpaid '
          'order${current == 1 ? '' : 's'} first.',
    _ => 'Reduce $label to $allowed.',
  };

  String get label => switch (limit) {
    'staff' => 'Staff accounts',
    'promos' => 'Active promos',
    'tables' => 'Tables',
    'rooms' => 'Rooms',
    'open_orders' => 'Open unpaid orders',
    _ => limit,
  };

  @override
  String toString() =>
      limit == 'open_orders'
          ? '$label: $current (settle or cancel them first)'
          : '$label: $current in use, plan allows $allowed (remove $mustRemove)';
}

class DowngradeBlockedException extends AdminActionException {
  final List<DowngradeBlocker> blockers;
  DowngradeBlockedException(this.blockers)
    : super(
        'Downgrade blocked:\n${blockers.map((b) => '• $b').join('\n')}',
      );
}

class AdminSubscriptionService {
  final _client = Supabase.instance.client;

  Future<void> _invoke(Map<String, dynamic> payload) async {
    try {
      final res = await _client.functions.invoke(
        'admin-subscription-action',
        body: payload,
      );
      // Defensive: in case an error body ever comes back as data.
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw AdminActionException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      // supabase_flutter throws on any non-2xx, so the 409 with the
      // blockers list lands here, not in res.data above.
      final d = e.details;
      if (e.status == 409 && d is Map && d['error'] == 'downgrade_blocked') {
        final raw = (d['blockers'] as List?) ?? const [];
        throw DowngradeBlockedException([
          for (final b in raw)
            DowngradeBlocker.fromMap(Map<String, dynamic>.from(b as Map)),
        ]);
      }
      final msg =
          d is Map && d['error'] != null
              ? d['error'].toString()
              : (e.reasonPhrase ?? 'Request failed (${e.status})');
      throw AdminActionException(msg);
    }
  }

  Future<void> changePlan({
    required String businessId,
    required String newPlan,
    DateTime? trialEndsAt,
    int? durationMonths,
    String? reason,
  }) => _invoke({
    'action': 'change_plan',
    'business_id': businessId,
    'new_plan': newPlan,
    if (trialEndsAt != null)
      'trial_ends_at': trialEndsAt.toUtc().toIso8601String(),
    if (durationMonths != null) 'duration_months': durationMonths,
    if (reason != null) 'reason': reason,
  });

  /// Read-only: lists what would block a move to [targetPlan]. An empty
  /// list means the business is eligible. Changes nothing.
  Future<List<DowngradeBlocker>> checkDowngrade({
    required String businessId,
    required String targetPlan,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'admin-subscription-action',
        body: {
          'action': 'check_downgrade',
          'business_id': businessId,
          'new_plan': targetPlan,
        },
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw AdminActionException(data['error'].toString());
      }
      final raw = (data is Map ? data['blockers'] : null) as List? ?? const [];
      return [
        for (final b in raw)
          DowngradeBlocker.fromMap(Map<String, dynamic>.from(b as Map)),
      ];
    } on FunctionException catch (e) {
      final d = e.details;
      throw AdminActionException(
        d is Map && d['error'] != null
            ? d['error'].toString()
            : (e.reasonPhrase ?? 'Request failed (${e.status})'),
      );
    }
  }

  Future<void> extendTrial({
    required String businessId,
    required DateTime trialEndsAt,
    String? reason,
  }) => _invoke({
    'action': 'extend',
    'business_id': businessId,
    'trial_ends_at': trialEndsAt.toUtc().toIso8601String(),
    if (reason != null) 'reason': reason,
  });

  Future<void> suspend({required String businessId, String? reason}) =>
      _invoke({
        'action': 'suspend',
        'business_id': businessId,
        if (reason != null) 'reason': reason,
      });

  Future<void> reactivate({required String businessId, String? reason}) =>
      _invoke({
        'action': 'reactivate',
        'business_id': businessId,
        if (reason != null) 'reason': reason,
      });

  /// `cancel` was removed as its own edge-function action (2026-09) — it
  /// previously defaulted new_plan to 'free', a tier that no longer exists
  /// in the starter/growth/pro model. Cancelling a subscription with no
  /// free tier to fall back to is the same operation as suspend(): keep
  /// the business's data and plan record intact, just mark it inactive.
  /// This method is kept only so existing call sites don't need to be
  /// hunted down individually — it's a thin alias for suspend().
  Future<void> cancel({required String businessId, String? reason}) =>
      suspend(businessId: businessId, reason: reason);
}

final adminSubscriptionServiceProvider = Provider<AdminSubscriptionService>((
  ref,
) {
  return AdminSubscriptionService();
});
