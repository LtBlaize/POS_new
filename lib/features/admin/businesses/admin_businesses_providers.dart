// lib/features/admin/businesses/admin_businesses_providers.dart
//
// Phase 6. Same defensive pattern as admin_dashboard_providers.dart:
// try/catch → empty on failure, no throwing into the UI.
//
// PAGINATION API ASSUMPTION: uses postgrest-dart v2's `.count(CountOption.exact)`
// terminal call, which returns a PostgrestResponse with both `.data` and
// `.count`. If this repo pins an older supabase_flutter/postgrest version,
// this call site (search for ".count(CountOption.exact)") is the only one
// that needs adjusting — the rest of the pagination logic doesn't care.
//
// "No secrets ever surfaced" (spec, Phase 6): the staff query below
// explicitly selects only id, name, role, is_active, created_at — never
// pin_hash / pin_salt. Don't widen that select() without re-checking this.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard/admin_dashboard_providers.dart' show RecentPayment, AdminActivityEntry;

const int kBusinessesPageSize = 20;

// ─────────────────────────────────────────────────────────────────────────
// FILTER STATE
// ─────────────────────────────────────────────────────────────────────────

enum ActiveFilter { all, active, inactive }

class BusinessFilter {
  final String search;
  final String? plan; // null = all plans
  final ActiveFilter activeFilter;
  final bool trialExpiringSoon; // trial_ends_at within next 7 days, still active

  const BusinessFilter({
    this.search = '',
    this.plan,
    this.activeFilter = ActiveFilter.all,
    this.trialExpiringSoon = false,
  });

  BusinessFilter copyWith({
    String? search,
    Object? plan = _sentinel,
    ActiveFilter? activeFilter,
    bool? trialExpiringSoon,
  }) =>
      BusinessFilter(
        search: search ?? this.search,
        plan: plan == _sentinel ? this.plan : plan as String?,
        activeFilter: activeFilter ?? this.activeFilter,
        trialExpiringSoon: trialExpiringSoon ?? this.trialExpiringSoon,
      );

  @override
  bool operator ==(Object other) =>
      other is BusinessFilter &&
      other.search == search &&
      other.plan == plan &&
      other.activeFilter == activeFilter &&
      other.trialExpiringSoon == trialExpiringSoon;

  @override
  int get hashCode => Object.hash(search, plan, activeFilter, trialExpiringSoon);
}

const _sentinel = Object();

final businessFilterProvider = StateProvider<BusinessFilter>((_) => const BusinessFilter());
final businessPageProvider = StateProvider<int>((_) => 0); // 0-indexed

// ─────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────

class BusinessListItem {
  final String id;
  final String name;
  final String businessType;
  final String subscriptionPlan;
  final bool isActive;
  final DateTime? trialEndsAt;
  final DateTime createdAt;

  const BusinessListItem({
    required this.id,
    required this.name,
    required this.businessType,
    required this.subscriptionPlan,
    required this.isActive,
    required this.trialEndsAt,
    required this.createdAt,
  });
}

class BusinessListPage {
  final List<BusinessListItem> items;
  final int totalCount;
  const BusinessListPage({required this.items, required this.totalCount});
  static const empty = BusinessListPage(items: [], totalCount: 0);

  int get totalPages => (totalCount / kBusinessesPageSize).ceil().clamp(1, 1 << 30);
}

class StaffSummary {
  final String id;
  final String name;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  const StaffSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });
}

class BusinessDetail {
  final String id;
  final String name;
  final String businessType;
  final String subscriptionPlan;
  final bool isActive;
  final String? address;
  final String? phone;
  final String? email;
  final String currency;
  final String timezone;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime createdAt;
  final List<RecentPayment> payments;
  final List<StaffSummary> staff;
  final List<AdminActivityEntry> activity;

  const BusinessDetail({
    required this.id,
    required this.name,
    required this.businessType,
    required this.subscriptionPlan,
    required this.isActive,
    required this.address,
    required this.phone,
    required this.email,
    required this.currency,
    required this.timezone,
    required this.trialStartedAt,
    required this.trialEndsAt,
    required this.createdAt,
    required this.payments,
    required this.staff,
    required this.activity,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// LIST PROVIDER
// ─────────────────────────────────────────────────────────────────────────

final businessListProvider =
    FutureProvider.autoDispose<BusinessListPage>((ref) async {
  final filter = ref.watch(businessFilterProvider);
  final page = ref.watch(businessPageProvider);

  try {
    final client = Supabase.instance.client;
    var query = client.from('businesses').select(
        'id, name, business_type, subscription_plan, is_active, trial_ends_at, created_at');

    if (filter.search.trim().isNotEmpty) {
      query = query.ilike('name', '%${filter.search.trim()}%');
    }
    if (filter.plan != null) {
      query = query.eq('subscription_plan', filter.plan!);
    }
    if (filter.activeFilter != ActiveFilter.all) {
      query = query.eq('is_active', filter.activeFilter == ActiveFilter.active);
    }
    if (filter.trialExpiringSoon) {
      final now = DateTime.now().toUtc();
      final soon = now.add(const Duration(days: 7));
      query = query
          .gte('trial_ends_at', now.toIso8601String())
          .lte('trial_ends_at', soon.toIso8601String());
    }

    final from = page * kBusinessesPageSize;
    final to = from + kBusinessesPageSize - 1;

    final response = await query
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final items = rows
        .map((r) => BusinessListItem(
              id: r['id'] as String,
              name: r['name'] as String,
              businessType: r['business_type'] as String? ?? 'unknown',
              subscriptionPlan: r['subscription_plan'] as String? ?? 'unknown',
              isActive: r['is_active'] as bool? ?? false,
              trialEndsAt: r['trial_ends_at'] != null
                  ? DateTime.parse(r['trial_ends_at'] as String).toLocal()
                  : null,
              createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
            ))
        .toList();

    return BusinessListPage(items: items, totalCount: response.count);
  } catch (_) {
    return BusinessListPage.empty;
  }
});

// Distinct plan values for the filter dropdown — pulled from live data
// rather than hardcoded, since we don't know the real enum values (flagged
// in Phase 5 too). Small table, fine to pull all rows for this.
final businessPlanOptionsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client.from('businesses').select('subscription_plan');
    final plans = (rows as List)
        .map((r) => r['subscription_plan'] as String? ?? 'unknown')
        .toSet()
        .toList()
      ..sort();
    return plans;
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────
// DETAIL PROVIDER
// ─────────────────────────────────────────────────────────────────────────

final businessDetailProvider =
    FutureProvider.family.autoDispose<BusinessDetail?, String>((ref, businessId) async {
  try {
    final client = Supabase.instance.client;

    final bizRow = await client
        .from('businesses')
        .select(
            'id, name, business_type, subscription_plan, is_active, address, phone, email, currency, timezone, trial_started_at, trial_ends_at, created_at')
        .eq('id', businessId)
        .maybeSingle();

    if (bizRow == null) return null;

    final paymentsRows = await client
        .from('payments')
        .select('id, amount, currency, status, provider, created_at')
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(20);

    final staffRows = await client
        .from('staff_members')
        // Explicitly NOT selecting pin_hash / pin_salt — see file header.
        .select('id, name, role, is_active, created_at')
        .eq('business_id', businessId)
        .order('created_at', ascending: false);

    // ASSUMPTION: admin_activity_logs.target_id stores the business id as
    // text when target_type = 'business' (e.g. logged by the Phase 2
    // Edge Function pattern on plan-change/suspend/reactivate actions).
    // If Phase 7's Edge Functions end up logging a different target_type
    // string, adjust the .eq('target_type', ...) filter below to match.
    final activityRows = await client
        .from('admin_activity_logs')
        .select('id, admin_user_id, action, target_type, target_id, created_at, admin_users(role)')
        .eq('target_type', 'business')
        .eq('target_id', businessId)
        .order('created_at', ascending: false)
        .limit(20);

    return BusinessDetail(
      id: bizRow['id'] as String,
      name: bizRow['name'] as String,
      businessType: bizRow['business_type'] as String? ?? 'unknown',
      subscriptionPlan: bizRow['subscription_plan'] as String? ?? 'unknown',
      isActive: bizRow['is_active'] as bool? ?? false,
      address: bizRow['address'] as String?,
      phone: bizRow['phone'] as String?,
      email: bizRow['email'] as String?,
      currency: bizRow['currency'] as String? ?? 'PHP',
      timezone: bizRow['timezone'] as String? ?? 'Asia/Manila',
      trialStartedAt: bizRow['trial_started_at'] != null
          ? DateTime.parse(bizRow['trial_started_at'] as String).toLocal()
          : null,
      trialEndsAt: bizRow['trial_ends_at'] != null
          ? DateTime.parse(bizRow['trial_ends_at'] as String).toLocal()
          : null,
      createdAt: DateTime.parse(bizRow['created_at'] as String).toLocal(),
      payments: (paymentsRows as List)
          .map((r) => RecentPayment(
                id: r['id'] as String,
                businessName: bizRow['name'] as String,
                amount: (r['amount'] as num?)?.toDouble() ?? 0,
                currency: r['currency'] as String? ?? 'PHP',
                status: r['status'] as String? ?? 'pending',
                provider: r['provider'] as String? ?? 'manual',
                createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
              ))
          .toList(),
      staff: (staffRows as List)
          .map((r) => StaffSummary(
                id: r['id'] as String,
                name: r['name'] as String,
                role: r['role'] as String? ?? 'cashier',
                isActive: r['is_active'] as bool? ?? false,
                createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
              ))
          .toList(),
      activity: (activityRows as List).map((r) {
        final adminUser = r['admin_users'] as Map<String, dynamic>?;
        final rawId = r['admin_user_id'] as String? ?? '';
        return AdminActivityEntry(
          id: r['id'] as String,
          adminRole: adminUser?['role'] as String? ?? 'unknown',
          adminIdShort: rawId.length >= 8 ? rawId.substring(0, 8) : rawId,
          action: r['action'] as String,
          targetType: r['target_type'] as String?,
          targetId: r['target_id'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        );
      }).toList(),
    );
  } catch (_) {
    return null;
  }
});