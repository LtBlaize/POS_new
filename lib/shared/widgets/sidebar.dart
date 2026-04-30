// lib/shared/widgets/sidebar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/feature_manager.dart';
import '../../core/providers/role_permissions_provider.dart';
import '../../features/auth/auth_provider.dart';
import 'app_colors.dart';
import '../../shared/widgets/offline_banner.dart';

class SidebarItem {
  final IconData icon;
  final String label;
  final String route;

  // requiredFeature  → business must have this feature enabled (e.g. 'kitchen')
  // requiredTab      → active staff role must have this tab in their permissions
  //                    (matches keys in role_permissions: 'pos', 'orders', etc.)
  //                    null = always visible regardless of role
  final String? requiredFeature;
  final String? requiredTab;

  const SidebarItem({
    required this.icon,
    required this.label,
    required this.route,
    this.requiredFeature,
    this.requiredTab,
  });
}

const _allItems = [
  SidebarItem(
    icon: Icons.point_of_sale,
    label: 'POS',
    route: '/pos',
    requiredTab: 'pos',
  ),
  SidebarItem(
    icon: Icons.receipt_long,
    label: 'Orders',
    route: '/orders',
    requiredTab: 'orders',
  ),
  SidebarItem(
    icon: Icons.kitchen,
    label: 'Kitchen',
    route: '/kitchen',
    requiredFeature: 'kitchen',
    requiredTab: 'kitchen',
  ),
  SidebarItem(
    icon: Icons.table_restaurant,
    label: 'Tables',
    route: '/tables',
    requiredFeature: 'tables',
    requiredTab: 'kitchen', // tables tab is part of kitchen role access
  ),
  SidebarItem(
    icon: Icons.inventory_2,
    label: 'Inventory',
    route: '/inventory',
    requiredFeature: 'inventory',
    requiredTab: 'inventory',
  ),
  SidebarItem(
    icon: Icons.account_balance_wallet_outlined,
    label: 'Utang',
    route: '/credits',
    requiredFeature: 'credits',
    requiredTab: 'utang',
  ),
  SidebarItem(
    icon: Icons.bar_chart_rounded,
    label: 'Reports',
    route: '/reports',
    requiredTab: 'reports',
  ),
  SidebarItem(
    icon: Icons.settings_outlined,
    label: 'Settings',
    route: '/settings',
    requiredTab: 'settings',
  ),
];

class Sidebar extends ConsumerWidget {
  final FeatureManager featureManager;
  final String currentRoute;

  const Sidebar({
    super.key,
    required this.featureManager,
    required this.currentRoute,
  });

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authServiceProvider).logout();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FIX: watch role-based tab permissions for the active staff member.
    // This is reactive — sidebar updates immediately when owner toggles
    // permissions in Settings, no restart required.
    final allowedTabs = ref.watch(activeStaffTabsProvider);

    final visibleItems = _allItems.where((item) {
      // 1. Business must have the feature enabled (e.g. kitchen toggle in config)
      if (item.requiredFeature != null &&
          !featureManager.hasFeature(item.requiredFeature!)) {
        return false;
      }
      // 2. Active staff role must have the tab in their permissions.
      //    Owner always gets everything (activeStaffTabsProvider returns kAllTabs
      //    for owner so this check passes automatically).
      if (item.requiredTab != null &&
          !allowedTabs.contains(item.requiredTab)) {
        return false;
      }
      return true;
    }).toList();

    return Container(
      width: 80,
      color: AppColors.sidebar,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 24),

          ...visibleItems.map((item) {
            final isActive = currentRoute == item.route;
            return Tooltip(
              message: item.label,
              preferBelow: false,
              child: GestureDetector(
                onTap: () =>
                    Navigator.pushReplacementNamed(context, item.route),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(
                      vertical: 4, horizontal: 10),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.accent.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isActive
                        ? Border.all(
                            color: AppColors.accent.withOpacity(0.4))
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isActive
                            ? AppColors.accent
                            : AppColors.textOnDark.withOpacity(0.5),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: isActive
                              ? AppColors.accent
                              : AppColors.textOnDark.withOpacity(0.5),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const Spacer(),
          const OfflineBanner(),

          Tooltip(
            message: 'Log out',
            preferBelow: false,
            child: GestureDetector(
              onTap: () => _logout(context, ref),
              child: Container(
                margin: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: AppColors.textOnDark.withOpacity(0.5),
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: AppColors.textOnDark.withOpacity(0.5),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}