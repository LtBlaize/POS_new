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

      final result = raw.map((role, tabs) => MapEntry(
            role,
            Set<String>.from(tabs as List).intersection(validTabs),
          ));

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

    final profile = ref.read(profileProvider).value;
    if (profile?.businessId == null) return;

    final client = ref.read(supabaseClientProvider);
    try {
      await client.from('business_configs').update({
        'role_permissions': updated.map(
          (r, tabs) => MapEntry(r, tabs.toList()),
        ),
      }).eq('business_id', profile!.businessId!);
    } catch (e) {
      debugPrint('[RolePermissions] save failed: $e');
    }
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