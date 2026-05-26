// lib/core/providers/role_permissions_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/staff.dart';
import '../providers/staff_provider.dart';
import '../../features/auth/auth_provider.dart';

// All tabs in the app
const kAllTabs = [
  'pos', 'orders', 'kitchen', 'inventory', 'utang', 'reports', 'settings'
];

// Tabs available per business type
const kRestaurantTabs = [
  'pos', 'orders', 'kitchen', 'inventory', 'utang', 'reports', 'settings'
];
const kRetailTabs = [
  'pos', 'orders', 'inventory', 'utang', 'reports', 'settings'
];

List<String> tabsForBusinessType(bool isRestaurant) =>
    isRestaurant ? kRestaurantTabs : kRetailTabs;

// Default permissions per role — restaurant
const kDefaultPermissions = <String, List<String>>{
  'manager': ['pos', 'orders', 'kitchen', 'inventory', 'utang', 'reports'],
  'cashier': ['pos', 'orders', 'utang'],
  'kitchen': ['kitchen'],
};

// Default permissions per role — retail
const kDefaultPermissionsRetail = <String, List<String>>{
  'cashier': ['pos', 'orders', 'utang'],
};

// ── State ─────────────────────────────────────────────────────────────────────

typedef RolePermMap = Map<String, Set<String>>;

class RolePermissionsNotifier extends AsyncNotifier<RolePermMap> {
  Future<void> refresh() async {
  state = const AsyncLoading();
  state = AsyncData(await build());
}
 @override
  Future<RolePermMap> build() async {
    final profile = await ref.watch(profileProvider.future);
    debugPrint('[Perms] businessId: ${profile?.businessId}');
    if (profile?.businessId == null) return _defaults();

    final client = ref.watch(supabaseClientProvider);
    try {
      final row = await client
          .from('business_configs')
          .select('role_permissions')
          .eq('business_id', profile!.businessId!)
          .maybeSingle();

      debugPrint('[Perms] raw from supabase: ${row?['role_permissions']}');

      final raw = row?['role_permissions'] as Map<String, dynamic>?;
      if (raw == null) return _defaults();

      final businessType = ref.read(businessTypeProvider);
      final isRestaurant = businessType?.isRestaurant ?? false;
      final validTabs = tabsForBusinessType(isRestaurant).toSet();

      // Handle both old format (List) and new format (Map with 'screens' key)
      final result = raw.map((role, value) {
        final List<dynamic> tabList = value is Map
            ? (value['screens'] as List? ?? [])
            : (value as List);
        return MapEntry(role, Set<String>.from(tabList).intersection(validTabs));
      });

      debugPrint('[Perms] resolved: $result');
      return result;
    } catch (e) {
      debugPrint('[RolePermissions] load failed: $e');
      return _defaults();
    }
  }

  RolePermMap _defaults() {
    final businessType = ref.read(businessTypeProvider);
    final isRestaurant = businessType?.isRestaurant ?? false;
    final source =
        isRestaurant ? kDefaultPermissions : kDefaultPermissionsRetail;
    return source.map((role, tabs) => MapEntry(role, Set<String>.from(tabs)));
  }


  Future<void> toggle(String role, String tab) async {
    final current = state.value ?? _defaults();
    final updated = Map<String, Set<String>>.from(
      current.map((r, tabs) => MapEntry(r, Set<String>.from(tabs))),
    );

    final roleTabs = updated[role] ?? {};
    if (roleTabs.contains(tab)) {
      roleTabs.remove(tab);
    } else {
      roleTabs.add(tab);
    }
    updated[role] = roleTabs;
    state = AsyncData(updated);

    // Persist — merge screens back into the existing capability map
    final profile = ref.read(profileProvider).value;
    if (profile?.businessId == null) return;

    final client = ref.read(supabaseClientProvider);
    try {
      // Read current raw JSONB so we preserve capability fields
      final row = await client
          .from('business_configs')
          .select('role_permissions')
          .eq('business_id', profile!.businessId!)
          .maybeSingle();

      final raw = (row?['role_permissions'] as Map<String, dynamic>?) ?? {};

      final merged = updated.map((r, tabs) {
        final existing = raw[r] is Map
            ? Map<String, dynamic>.from(raw[r] as Map)
            : <String, dynamic>{};
        existing['screens'] = tabs.toList();
        return MapEntry(r, existing);
      });

      await client.from('business_configs').update({
        'role_permissions': merged,
      }).eq('business_id', profile.businessId!);
    } catch (e) {
      debugPrint('[RolePermissions] save failed: $e');
    }
  }

  /// Returns a capability value for the active staff's role.
  /// Owner always returns the permissive default.
  /// Falls back to [defaultValue] if the key isn't in the JSONB.
  T capability<T>(String role, String key, T defaultValue) {
    if (role == 'owner') return defaultValue;
    // Synchronous read from cached state isn't possible for raw JSONB —
    // use activeRoleCapabilitiesProvider instead for reactive reads.
    return defaultValue;
  }

  // Use ref.watch(rolePermissionsProvider) directly in widgets for reactivity.
  // This helper is for one-off imperative checks only.
  bool hasTab(String role, String tab) {
    if (role == 'owner') return true;
    final perms = state.value ?? _defaults();
    return perms[role]?.contains(tab) ?? false;
  }
}

final rolePermissionsProvider =
    AsyncNotifierProvider<RolePermissionsNotifier, RolePermMap>(
        RolePermissionsNotifier.new);

// Correctly resolves tabs for whoever is actually logged in
// ── Role capabilities (action-level) ─────────────────────────────────────────

/// Fetches the full capability map for the active staff's role.
/// Returns permissive defaults for owner, restrictive defaults on error.
final activeRoleCapabilitiesProvider =
    FutureProvider<RoleCapabilities>((ref) async {
  final staff = ref.watch(activeStaffProvider);
  if (staff == null) return RoleCapabilities.none;
  if (staff.role == StaffRole.owner) return RoleCapabilities.owner;

  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) return RoleCapabilities.none;

  final client = ref.read(supabaseClientProvider);
  try {
    final row = await client
        .from('business_configs')
        .select('role_permissions')
        .eq('business_id', profile!.businessId!)
        .maybeSingle();

    final raw = row?['role_permissions'] as Map<String, dynamic>?;
    final roleData = raw?[staff.role.value] as Map<String, dynamic>?;
    if (roleData == null) return RoleCapabilities.defaultFor(staff.role);

    return RoleCapabilities.fromJson(roleData);
  } catch (_) {
    return RoleCapabilities.defaultFor(staff.role);
  }
});

class RoleCapabilities {
  final bool canVoidItem;
  final bool canVoidOrder;
  final bool canApplyDiscount;
  final bool canIssueRefund;
  final bool requiresManagerForDiscount;
  final int maxDiscountPercent;

  const RoleCapabilities({
    required this.canVoidItem,
    required this.canVoidOrder,
    required this.canApplyDiscount,
    required this.canIssueRefund,
    required this.requiresManagerForDiscount,
    required this.maxDiscountPercent,
  });

  factory RoleCapabilities.fromJson(Map<String, dynamic> json) =>
      RoleCapabilities(
        canVoidItem: json['can_void_item'] as bool? ?? false,
        canVoidOrder: json['can_void_order'] as bool? ?? false,
        canApplyDiscount: json['can_apply_discount'] as bool? ?? false,
        canIssueRefund: json['can_issue_refund'] as bool? ?? false,
        requiresManagerForDiscount:
            json['requires_manager_for_discount'] as bool? ?? true,
        maxDiscountPercent:
            (json['max_discount_percent'] as num?)?.toInt() ?? 0,
      );

  static const owner = RoleCapabilities(
    canVoidItem: true,
    canVoidOrder: true,
    canApplyDiscount: true,
    canIssueRefund: true,
    requiresManagerForDiscount: false,
    maxDiscountPercent: 100,
  );

  static const none = RoleCapabilities(
    canVoidItem: false,
    canVoidOrder: false,
    canApplyDiscount: false,
    canIssueRefund: false,
    requiresManagerForDiscount: true,
    maxDiscountPercent: 0,
  );

  static RoleCapabilities defaultFor(StaffRole role) => switch (role) {
        StaffRole.manager => const RoleCapabilities(
            canVoidItem: true,
            canVoidOrder: true,
            canApplyDiscount: true,
            canIssueRefund: true,
            requiresManagerForDiscount: false,
            maxDiscountPercent: 50,
          ),
        StaffRole.cashier => const RoleCapabilities(
            canVoidItem: false,
            canVoidOrder: false,
            canApplyDiscount: true,
            canIssueRefund: false,
            requiresManagerForDiscount: true,
            maxDiscountPercent: 10,
          ),
        _ => none,
      };
}

final activeStaffTabsProvider = Provider<Set<String>>((ref) {
  final staff = ref.watch(activeStaffProvider);
  debugPrint('[Tabs] activeStaff: ${staff?.name} role: ${staff?.role.value}');
  if (staff == null) return {};
  if (staff.role == StaffRole.owner) return kAllTabs.toSet();

  final permsAsync = ref.watch(rolePermissionsProvider);
  debugPrint('[Tabs] permsAsync state: $permsAsync');

  if (permsAsync.isLoading) return {};

  final perms = permsAsync.value ??
      kDefaultPermissions.map(
        (r, tabs) => MapEntry(r, Set<String>.from(tabs)),
      );

  final tabs = perms[staff.role.value] ?? {};
  debugPrint('[Tabs] tabs for ${staff.role.value}: $tabs');
  return tabs;
});