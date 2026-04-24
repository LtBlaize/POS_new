// lib/features/pos/pos_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/services/feature_manager.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/pin_lock_overlay.dart';
import '../credits/credits_screen.dart';

import '../inventory/inventory_screen.dart';
import '../kitchen/kitchen_screen.dart';
import '../orders/orders_screen.dart';
import '../reports/reports_screen.dart';
import '../tables/table_selector.dart';
import '../settings/settings_screen.dart';

import 'widgets/product/product_grid.dart';
import 'widgets/cart_panel.dart';
import 'widgets/layout/top_bar.dart';
import 'widgets/category_bar.dart';

import '../../core/providers/cart_provider.dart';

final _activeIndexProvider = StateProvider<int>((ref) => 0);

class POSScreen extends ConsumerWidget {
  final FeatureManager featureManager;

  const POSScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = ref.watch(_activeIndexProvider);
    final activeStaff = ref.watch(activeStaffProvider);
    final role = activeStaff?.role ?? StaffRole.cashier;
    final screens = _buildScreens(featureManager, role);

    // Clamp index if screens shrink (e.g. cashier has fewer tabs than owner)
    final safeIndex = activeIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: PinLockOverlay(
        child: Row(
          children: [
            _AdaptiveSidebar(
              featureManager: featureManager,
              activeIndex: safeIndex,
              screens: screens,
              onSelect: (i) =>
                  ref.read(_activeIndexProvider.notifier).state = i,
            ),
            Expanded(
              child: IndexedStack(
                index: safeIndex,
                children: screens.map((s) => s.widget).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_ScreenEntry> _buildScreens(FeatureManager fm, StaffRole role) {
    return [
      if (role.canAccessPOS)
        _ScreenEntry(
          icon: Icons.point_of_sale_rounded,
          label: 'POS',
          widget: _POSMain(featureManager: fm),
        ),
      if (role.canAccessOrders)
        _ScreenEntry(
          icon: Icons.receipt_long_rounded,
          label: 'Orders',
          widget: OrdersScreen(featureManager: fm),
        ),
      if (fm.hasFeature('kitchen') && role.canAccessKitchen)
        _ScreenEntry(
          icon: Icons.kitchen_rounded,
          label: 'Kitchen',
          widget: const KitchenScreen(),
        ),
      if (fm.hasFeature('inventory') && role.canAccessInventory)
        _ScreenEntry(
          icon: Icons.inventory_2_rounded,
          label: 'Inventory',
          widget: const InventoryScreen(),
        ),
        // ← ADD THIS
        _ScreenEntry(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Utang',
          widget: CreditsScreen(featureManager: fm), 
        ),
      if (role.canAccessReports)
        _ScreenEntry(
          icon: Icons.bar_chart_rounded,
          label: 'Reports',
          widget: ReportsScreen(featureManager: fm),
        ),
      if (role.canAccessSettings)
        _ScreenEntry(
          icon: Icons.settings_outlined,
          label: 'Settings',
          widget: SettingsScreen(featureManager: fm),
        ),
    ];
  }
}

// ── POS MAIN ──────────────────────────────────────────────────────────────────

class _POSMain extends StatelessWidget {
  final FeatureManager featureManager;

  const _POSMain({required this.featureManager});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              const TopBar(),
              if (featureManager.hasFeature('tables'))
                const TableSelector(),
              const CategoryBar(),
              const Expanded(child: ProductGrid()),
            ],
          ),
        ),
        CartPanel(featureManager: featureManager),
      ],
    );
  }
}

// ── SIDEBAR ───────────────────────────────────────────────────────────────────

class _AdaptiveSidebar extends ConsumerWidget {
  final FeatureManager featureManager;
  final int activeIndex;
  final List<_ScreenEntry> screens;
  final ValueChanged<int> onSelect;

  const _AdaptiveSidebar({
    required this.featureManager,
    required this.activeIndex,
    required this.screens,
    required this.onSelect,
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
    ref.read(cartProvider.notifier).clear();
    ref.read(activeStaffProvider.notifier).logout();
    ref.read(appLockedProvider.notifier).state = true;

    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeStaff = ref.watch(activeStaffProvider);

    return Container(
      width: 80,
      color: const Color(0xFF16213E),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Logo — fixed top
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE94560),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 28),
          ),

          const SizedBox(height: 12),

          // Active staff chip — fixed top
          if (activeStaff != null)
            Tooltip(
              message: '${activeStaff.name} (${activeStaff.role.label})',
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _roleColor(activeStaff.role).withOpacity(0.2),
                  border: Border.all(
                    color: _roleColor(activeStaff.role).withOpacity(0.6),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    activeStaff.name[0].toUpperCase(),
                    style: TextStyle(
                      color: _roleColor(activeStaff.role),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ── Scrollable nav items ──────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  ...screens.asMap().entries.map((entry) {
                    final i = entry.key;
                    final screen = entry.value;
                    final isActive = activeIndex == i;

                    return Tooltip(
                      message: screen.label,
                      child: GestureDetector(
                        onTap: () => onSelect(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 10),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFE94560).withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: isActive
                                ? Border.all(
                                    color: const Color(0xFFE94560)
                                        .withOpacity(0.4))
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                screen.icon,
                                color: isActive
                                    ? const Color(0xFFE94560)
                                    : Colors.white.withOpacity(0.4),
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                screen.label,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isActive
                                      ? const Color(0xFFE94560)
                                      : Colors.white.withOpacity(0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ── Fixed bottom: Lock + Logout ───────────────────────
          const Divider(color: Colors.white12, height: 1),

          // Lock button
          Tooltip(
            message: 'Lock',
            child: GestureDetector(
              onTap: () {
                ref.read(activeStaffProvider.notifier).logout();
                ref.read(appLockedProvider.notifier).state = true;
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        color: Colors.white.withOpacity(0.4), size: 22),
                    const SizedBox(height: 4),
                    Text(
                      'Lock',
                      style: TextStyle(
                          fontSize: 9, color: Colors.white.withOpacity(0.4)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Logout
          Tooltip(
            message: 'Log out',
            child: GestureDetector(
              onTap: () => _logout(context, ref),
              child: Container(
                margin: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Icon(Icons.logout_rounded,
                        color: Colors.white.withOpacity(0.4), size: 22),
                    const SizedBox(height: 4),
                    Text(
                      'Logout',
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.white.withOpacity(0.4)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Color _roleColor(StaffRole role) => switch (role) {
        StaffRole.owner => const Color(0xFFE94560),
        StaffRole.manager => const Color(0xFF4CAF50),
        StaffRole.cashier => const Color(0xFF2196F3),
        StaffRole.kitchen => const Color(0xFFFF9800),
      };
}

// ── MODEL ─────────────────────────────────────────────────────────────────────

class _ScreenEntry {
  final IconData icon;
  final String label;
  final Widget widget;

  const _ScreenEntry({
    required this.icon,
    required this.label,
    required this.widget,
  });
}