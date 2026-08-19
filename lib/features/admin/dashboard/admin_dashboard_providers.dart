// lib/features/admin/dashboard/admin_dashboard_providers.dart
//
// Phase 5. Mirrors features/reports/reports_providers.dart's pattern:
// one FutureProvider per widget, business_id scoping swapped for "no scope
// at all" (platform-wide), try/catch → empty/zero rather than throwing so a
// single failed query doesn't blank the whole dashboard.
//
// ASSUMPTION (flagged per admin_provider.dart's own convention): Supabase
// client access mirrors reports_providers.dart's `supabaseClientProvider`.
// If that's actually named differently, only the `ref.watch(supabaseClientProvider)`
// call sites below need updating.
//
// RLS DEPENDENCY: every query here relies on Phase 2's RLS actually granting
// admin_users rows read access to businesses/payments/admin_activity_logs.
// If Phase 2's policies aren't applied yet, every provider below will
// silently return empty/zero (caught by the try/catch) rather than error —
// worth manually verifying against a real admin session before trusting
// blank cards mean "no data" vs "RLS not applied."

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────

class DashboardKpis {
  final int totalBusinesses;
  final int activeSubscriptions; // is_active=true AND subscription_plan != 'free'
  final double monthlyRevenue;   // sum(payments.amount) where status='completed', this calendar month
  final Map<String, int> planCounts; // raw subscription_plan value -> count, for "Active X" cards

  const DashboardKpis({
    required this.totalBusinesses,
    required this.activeSubscriptions,
    required this.monthlyRevenue,
    required this.planCounts,
  });

  static const empty = DashboardKpis(
    totalBusinesses: 0,
    activeSubscriptions: 0,
    monthlyRevenue: 0,
    planCounts: {},
  );
}

class MonthlyRevenuePoint {
  final DateTime month; // first-of-month, local
  final double amount;
  const MonthlyRevenuePoint(this.month, this.amount);
}

class PlanBreakdown {
  final String plan; // raw enum text, whatever it is
  final int count;
  final double pct; // 0-100, of businesses with a non-null plan
  const PlanBreakdown(this.plan, this.count, this.pct);
}

class RecentBusiness {
  final String id;
  final String name;
  final String subscriptionPlan;
  final bool isActive;
  final DateTime createdAt;
  const RecentBusiness({
    required this.id,
    required this.name,
    required this.subscriptionPlan,
    required this.isActive,
    required this.createdAt,
  });
}

class RecentPayment {
  final String id;
  final String businessName;
  final double amount;
  final String currency;
  final String status;
  final String provider;
  final DateTime createdAt;
  const RecentPayment({
    required this.id,
    required this.businessName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.provider,
    required this.createdAt,
  });
}

class AdminActivityEntry {
  final String id;
  final String adminRole;   // from admin_users.role — no name field exists yet, see file header
  final String adminIdShort; // first 8 chars of admin_user_id, for eyeballing "was this the same admin"
  final String action;
  final String? targetType;
  final String? targetId;
  final DateTime createdAt;
  const AdminActivityEntry({
    required this.id,
    required this.adminRole,
    required this.adminIdShort,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────

final dashboardKpisProvider = FutureProvider<DashboardKpis>((ref) async {
  try {
    final client = Supabase.instance.client;

    // Total businesses + plan breakdown in one pass.
    final bizRows = await client
        .from('businesses')
        .select('subscription_plan, is_active');

    final rows = (bizRows as List).cast<Map<String, dynamic>>();
    final planCounts = <String, int>{};
    int activeSubs = 0;
    for (final r in rows) {
      final plan = r['subscription_plan'] as String? ?? 'unknown';
      final isActive = r['is_active'] as bool? ?? false;
      planCounts[plan] = (planCounts[plan] ?? 0) + 1;
      if (isActive && plan != 'free') activeSubs++;
    }

    // Monthly revenue: completed payments this calendar month.
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toUtc().toIso8601String();
    final payRows = await client
        .from('payments')
        .select('amount')
        .eq('status', 'completed')
        .gte('created_at', monthStart);

    final monthlyRevenue = (payRows as List).fold<double>(
      0,
      (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0),
    );

    return DashboardKpis(
      totalBusinesses: rows.length,
      activeSubscriptions: activeSubs,
      monthlyRevenue: monthlyRevenue,
      planCounts: planCounts,
    );
  } catch (_) {
    return DashboardKpis.empty;
  }
});

/// Last 6 completed months of revenue, oldest first. Empty list (not zeros)
/// when there's no payment history at all — screen must render an empty
/// state, not a flat zero line that implies "confirmed zero revenue."
final dashboardRevenueChartProvider =
    FutureProvider<List<MonthlyRevenuePoint>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month - 5, 1);

    final rows = await client
        .from('payments')
        .select('amount, created_at')
        .eq('status', 'completed')
        .gte('created_at', rangeStart.toUtc().toIso8601String());

    if ((rows as List).isEmpty) return [];

    final Map<String, double> byMonth = {}; // 'yyyy-MM' -> sum
    for (final r in rows) {
      final dt = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final amt = (r['amount'] as num?)?.toDouble() ?? 0;
      byMonth[key] = (byMonth[key] ?? 0) + amt;
    }

    final points = <MonthlyRevenuePoint>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      points.add(MonthlyRevenuePoint(m, byMonth[key] ?? 0));
    }
    return points;
  } catch (_) {
    return [];
  }
});

final dashboardSubscriptionBreakdownProvider =
    FutureProvider<List<PlanBreakdown>>((ref) async {
  final kpis = await ref.watch(dashboardKpisProvider.future);
  final total = kpis.planCounts.values.fold<int>(0, (s, c) => s + c);
  if (total == 0) return [];

  final entries = kpis.planCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return entries
      .map((e) => PlanBreakdown(e.key, e.value, e.value / total * 100))
      .toList();
});

final dashboardRecentBusinessesProvider =
    FutureProvider<List<RecentBusiness>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client
        .from('businesses')
        .select('id, name, subscription_plan, is_active, created_at')
        .order('created_at', ascending: false)
        .limit(5);

    return (rows as List)
        .map((r) => RecentBusiness(
              id: r['id'] as String,
              name: r['name'] as String,
              subscriptionPlan: r['subscription_plan'] as String? ?? 'unknown',
              isActive: r['is_active'] as bool? ?? false,
              createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
            ))
        .toList();
  } catch (_) {
    return [];
  }
});

final dashboardRecentPaymentsProvider =
    FutureProvider<List<RecentPayment>>((ref) async {
  try {
    final client = Supabase.instance.client;
    // No FK-based embed to businesses in the schema shown for payments →
    // businesses; embedding via `businesses(name)` should work since
    // payments.business_id references businesses.id, but if PostgREST
    // complains about ambiguous/missing relationship, fall back to two
    // queries (id list, then a `.in_` lookup on businesses).
    final rows = await client
        .from('payments')
        .select('id, amount, currency, status, provider, created_at, businesses(name)')
        .order('created_at', ascending: false)
        .limit(5);

    return (rows as List).map((r) {
      final biz = r['businesses'] as Map<String, dynamic>?;
      return RecentPayment(
        id: r['id'] as String,
        businessName: biz?['name'] as String? ?? 'Unknown business',
        amount: (r['amount'] as num?)?.toDouble() ?? 0,
        currency: r['currency'] as String? ?? 'PHP',
        status: r['status'] as String? ?? 'pending',
        provider: r['provider'] as String? ?? 'manual',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
    }).toList();
  } catch (_) {
    return [];
  }
});

final dashboardActivityFeedProvider =
    FutureProvider<List<AdminActivityEntry>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client
        .from('admin_activity_logs')
        .select('id, admin_user_id, action, target_type, target_id, created_at, admin_users(role)')
        .order('created_at', ascending: false)
        .limit(8);

    return (rows as List).map((r) {
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
    }).toList();
  } catch (_) {
    return [];
  }
});