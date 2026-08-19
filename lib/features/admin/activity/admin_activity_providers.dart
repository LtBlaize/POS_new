// lib/features/admin/activity/admin_activity_providers.dart
//
// Phase 10. Read-only, filterable view over admin_activity_logs. Reuses
// AdminActivityEntry from the dashboard rather than a second model — same
// row shape, just a longer list with filters instead of a capped-at-8 feed.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard/admin_dashboard_providers.dart' show AdminActivityEntry;

const int kActivityPageSize = 30;

class ActivityFilter {
  final String? action;      // null = all
  final String? targetType;  // null = all
  final String? adminUserId; // null = all; filters by admin_users.id

  const ActivityFilter({this.action, this.targetType, this.adminUserId});

  ActivityFilter copyWith({
    Object? action = _sentinel,
    Object? targetType = _sentinel,
    Object? adminUserId = _sentinel,
  }) =>
      ActivityFilter(
        action: action == _sentinel ? this.action : action as String?,
        targetType: targetType == _sentinel ? this.targetType : targetType as String?,
        adminUserId: adminUserId == _sentinel ? this.adminUserId : adminUserId as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ActivityFilter &&
      other.action == action &&
      other.targetType == targetType &&
      other.adminUserId == adminUserId;

  @override
  int get hashCode => Object.hash(action, targetType, adminUserId);
}

const _sentinel = Object();

final activityFilterProvider = StateProvider<ActivityFilter>((_) => const ActivityFilter());
final activityPageProvider = StateProvider<int>((_) => 0);

class ActivityListPage {
  final List<AdminActivityEntry> items;
  final int totalCount;
  const ActivityListPage({required this.items, required this.totalCount});
  static const empty = ActivityListPage(items: [], totalCount: 0);
  int get totalPages => (totalCount / kActivityPageSize).ceil().clamp(1, 1 << 30);
}

final activityListProvider = FutureProvider.autoDispose<ActivityListPage>((ref) async {
  final filter = ref.watch(activityFilterProvider);
  final page = ref.watch(activityPageProvider);

  try {
    final client = Supabase.instance.client;
    var query = client
        .from('admin_activity_logs')
        .select('id, admin_user_id, action, target_type, target_id, created_at, admin_users(role)');

    if (filter.action != null) query = query.eq('action', filter.action!);
    if (filter.targetType != null) query = query.eq('target_type', filter.targetType!);
    if (filter.adminUserId != null) query = query.eq('admin_user_id', filter.adminUserId!);

    final from = page * kActivityPageSize;
    final to = from + kActivityPageSize - 1;

    final response = await query
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final items = rows.map((r) {
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

    return ActivityListPage(items: items, totalCount: response.count);
  } catch (_) {
    return ActivityListPage.empty;
  }
});

/// Distinct action values for the filter dropdown, pulled from live data
/// (same reasoning as businessPlanOptionsProvider in Phase 6 — we don't
/// hardcode an enum here since `action` is free-text, not a Postgres enum).
final activityActionOptionsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client.from('admin_activity_logs').select('action').limit(500);
    final actions = (rows as List).map((r) => r['action'] as String).toSet().toList()..sort();
    return actions;
  } catch (_) {
    return [];
  }
});

final activityTargetTypeOptionsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client
        .from('admin_activity_logs')
        .select('target_type')
        .not('target_type', 'is', null)
        .limit(500);
    final types = (rows as List).map((r) => r['target_type'] as String).toSet().toList()..sort();
    return types;
  } catch (_) {
    return [];
  }
});

class AdminUserOption {
  final String id;
  final String role;
  const AdminUserOption(this.id, this.role);
}

/// For the "admin" filter dropdown. Labeled by role + short id since there's
/// no display name column yet (see file header note).
final adminUserOptionsProvider = FutureProvider.autoDispose<List<AdminUserOption>>((ref) async {
  try {
    final client = Supabase.instance.client;
    final rows = await client.from('admin_users').select('id, role').order('role');
    return (rows as List)
        .map((r) => AdminUserOption(r['id'] as String, r['role'] as String? ?? 'unknown'))
        .toList();
  } catch (_) {
    return [];
  }
});