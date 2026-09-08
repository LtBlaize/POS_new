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

class AdminSubscriptionService {
  final _client = Supabase.instance.client;

  Future<void> _invoke(Map<String, dynamic> payload) async {
    final res = await _client.functions.invoke(
      'admin-subscription-action',
      body: payload,
    );
    // FunctionsClient throws FunctionException on non-2xx in v2, but guard
    // defensively anyway in case the error body comes back as data instead.
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw AdminActionException(data['error'] as String);
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
        if (trialEndsAt != null) 'trial_ends_at': trialEndsAt.toUtc().toIso8601String(),
        if (durationMonths != null) 'duration_months': durationMonths,
        if (reason != null) 'reason': reason,
      });

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

  Future<void> suspend({required String businessId, String? reason}) => _invoke({
        'action': 'suspend',
        'business_id': businessId,
        if (reason != null) 'reason': reason,
      });

  Future<void> reactivate({required String businessId, String? reason}) => _invoke({
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

final adminSubscriptionServiceProvider = Provider<AdminSubscriptionService>((ref) {
  return AdminSubscriptionService();
});