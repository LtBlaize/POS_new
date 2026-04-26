// lib/core/providers/role_permissions_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/auth_provider.dart';

// All tabs in the app
const kAllTabs = ['pos', 'orders', 'kitchen', 'inventory', 'utang', 'reports', 'settings'];

// Tabs available per business type (kitchen excluded from retail)
const kRestaurantTabs = ['pos', 'orders', 'kitchen', 'inventory', 'utang', 'reports', 'settings'];
const kRetailTabs     = ['pos', 'orders', 'inventory', 'utang', 'reports', 'settings'];

List<String> tabsForBusinessType(bool isRestaurant) =>
    isRestaurant ? kRestaurantTabs : kRetailTabs;

// Default permissions per role — restaurant (has kitchen + manager)
const kDefaultPermissions = <String, List<String>>{
  'manager': ['pos', 'orders', 'kitchen', 'inventory', 'utang', 'reports'],
  'cashier': ['pos', 'orders', 'utang'],
  'kitchen': ['kitchen'],
};

// Default permissions per role — retail (cashier only, no kitchen tab)
const kDefaultPermissionsRetail = <String, List<String>>{
  'cashier': ['pos', 'orders', 'utang'],
};

// ── State ─────────────────────────────────────────────────────────────────────

typedef RolePermMap = Map<String, Set<String>>;

class RolePermissionsNotifier extends AsyncNotifier<RolePermMap> {
  @override
  Future<RolePermMap> build() async {
    final profile = await ref.watch(profileProvider.future);
    if (profile?.businessId == null) return _defaults();

    final client = ref.watch(supabaseClientProvider);
    try {
      final row = await client
          .from('business_configs')
          .select('role_permissions')
          .eq('business_id', profile!.businessId!)
          .maybeSingle();

      final raw = row?['role_permissions'] as Map<String, dynamic>?;
      if (raw == null) return _defaults();

      // Filter out any tabs that don't belong to this business type
      final businessType = ref.read(businessTypeProvider);
      final isRestaurant = businessType?.isRestaurant ?? false;
      final validTabs = tabsForBusinessType(isRestaurant).toSet();

      return raw.map((role, tabs) => MapEntry(
            role,
            Set<String>.from(tabs as List).intersection(validTabs),
          ));
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
    return source.map(
      (role, tabs) => MapEntry(role, Set<String>.from(tabs)),
    );
  }

  // Toggle a single tab for a role and persist
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

    // Persist to Supabase
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

  // Check if a role has access to a tab
  bool hasTab(String role, String tab) {
    if (role == 'owner') return true; // owner always has everything
    final perms = state.value ?? _defaults();
    return perms[role]?.contains(tab) ?? false;
  }
}

final rolePermissionsProvider =
    AsyncNotifierProvider<RolePermissionsNotifier, RolePermMap>(
        RolePermissionsNotifier.new);

// Convenience: get allowed tabs for the active staff's role
final activeStaffTabsProvider = Provider<Set<String>>((ref) {
  final permsAsync = ref.watch(rolePermissionsProvider);
  final perms = permsAsync.value ??
      kDefaultPermissions.map(
        (r, tabs) => MapEntry(r, Set<String>.from(tabs)),
      );
  // This is read in pos_screen — role is passed there directly
  return perms['cashier'] ?? {};
});