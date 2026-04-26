// lib/features/pos/pos_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/staff.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/role_permissions_provider.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/services/feature_manager.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/pin_lock_overlay.dart';
import '../credits/credits_screen.dart';
import '../inventory/inventory_screen.dart';
import '../kitchen/kitchen_screen.dart';
import '../orders/orders_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../tables/table_selector.dart';
import 'widgets/cart_panel.dart';
import 'widgets/category_bar.dart';
import 'widgets/layout/top_bar.dart';
import 'widgets/product/product_grid.dart';

final _activeIndexProvider = StateProvider<int>((ref) => 0);

// ── Layout mode ───────────────────────────────────────────────────────────────

enum _Layout {
  phonePortrait,   // w < 600, portrait  — bottom nav + bottom-sheet cart
  phoneLandscape,  // w < 900, landscape — compact sidebar + narrow cart
  tabletPortrait,  // w >= 600, portrait — compact sidebar + bottom-sheet cart
  tabletLandscape, // w >= 900, landscape — full sidebar + full cart panel
}

_Layout _layoutOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final isPortrait = size.height > size.width;
  final w = size.width;
  if (isPortrait && w < 600) return _Layout.phonePortrait;
  if (!isPortrait && w < 900) return _Layout.phoneLandscape;
  if (isPortrait) return _Layout.tabletPortrait;
  return _Layout.tabletLandscape;
}

// ── Root ──────────────────────────────────────────────────────────────────────

class POSScreen extends ConsumerWidget {
  final FeatureManager featureManager;
  const POSScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = _layoutOf(context);
    final activeIndex = ref.watch(_activeIndexProvider);
    final activeStaff = ref.watch(activeStaffProvider);
    final role = activeStaff?.role ?? StaffRole.cashier;
    final perms = ref.watch(rolePermissionsProvider).value ?? {};
    final screens = _buildScreens(featureManager, role, perms, layout);
    final safeIndex = activeIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: PinLockOverlay(
        child: switch (layout) {
          _Layout.phonePortrait || _Layout.tabletPortrait => _PortraitShell(
              featureManager: featureManager,
              screens: screens,
              activeIndex: safeIndex,
              layout: layout,
              onSelect: (i) =>
                  ref.read(_activeIndexProvider.notifier).state = i,
            ),
          _Layout.phoneLandscape || _Layout.tabletLandscape => _LandscapeShell(
              featureManager: featureManager,
              screens: screens,
              activeIndex: safeIndex,
              layout: layout,
              onSelect: (i) =>
                  ref.read(_activeIndexProvider.notifier).state = i,
            ),
        },
      ),
    );
  }

  List<_ScreenEntry> _buildScreens(
    FeatureManager fm,
    StaffRole role,
    Map<String, Set<String>> perms,
    _Layout layout,
  ) {
    bool allowed(String tab) =>
        role == StaffRole.owner || (perms[role.key]?.contains(tab) ?? false);

    return [
      if (allowed('pos') && role.canAccessPOS)
        _ScreenEntry(
          icon: Icons.point_of_sale_rounded,
          label: 'POS',
          widget: _POSMain(featureManager: fm, layout: layout),
        ),
      if (allowed('orders') && role.canAccessOrders)
        _ScreenEntry(
          icon: Icons.receipt_long_rounded,
          label: 'Orders',
          widget: OrdersScreen(featureManager: fm),
        ),
      if (allowed('kitchen') && fm.hasFeature('kitchen') && role.canAccessKitchen)
        _ScreenEntry(
          icon: Icons.kitchen_rounded,
          label: 'Kitchen',
          widget: const KitchenScreen(),
        ),
      if (allowed('inventory') && fm.hasFeature('inventory') && role.canAccessInventory)
        _ScreenEntry(
          icon: Icons.inventory_2_rounded,
          label: 'Inventory',
          widget: const InventoryScreen(),
        ),
      if (allowed('utang'))
        _ScreenEntry(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Utang',
          widget: CreditsScreen(featureManager: fm),
        ),
      if (allowed('reports') && role.canAccessReports)
        _ScreenEntry(
          icon: Icons.bar_chart_rounded,
          label: 'Reports',
          widget: ReportsScreen(featureManager: fm),
        ),
      if (allowed('settings') && role.canAccessSettings)
        _ScreenEntry(
          icon: Icons.settings_outlined,
          label: 'Settings',
          widget: SettingsScreen(featureManager: fm),
        ),
    ];
  }
}

// ── Portrait shell ────────────────────────────────────────────────────────────

class _PortraitShell extends ConsumerWidget {
  final FeatureManager featureManager;
  final List<_ScreenEntry> screens;
  final int activeIndex;
  final _Layout layout;
  final ValueChanged<int> onSelect;

  const _PortraitShell({
    required this.featureManager,
    required this.screens,
    required this.activeIndex,
    required this.layout,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final itemCount = cartItems.fold(0, (sum, i) => sum + i.quantity);
    final isPOS = activeIndex == 0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: activeIndex,
        children: screens.map((s) => s.widget).toList(),
      ),
      floatingActionButton: isPOS && itemCount > 0
          ? _CartFAB(
              itemCount: itemCount,
              onTap: () => _showCartSheet(context),
            )
          : null,
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomNav(
        screens: screens,
        activeIndex: activeIndex,
        onSelect: onSelect,
      ),
    );
  }

  void _showCartSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, _) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: CartPanel(featureManager: featureManager),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Landscape shell ───────────────────────────────────────────────────────────

class _LandscapeShell extends StatelessWidget {
  final FeatureManager featureManager;
  final List<_ScreenEntry> screens;
  final int activeIndex;
  final _Layout layout;
  final ValueChanged<int> onSelect;

  const _LandscapeShell({
    required this.featureManager,
    required this.screens,
    required this.activeIndex,
    required this.layout,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AdaptiveSidebar(
          activeIndex: activeIndex,
          screens: screens,
          layout: layout,
          onSelect: onSelect,
        ),
        Expanded(
          child: IndexedStack(
            index: activeIndex,
            children: screens.map((s) => s.widget).toList(),
          ),
        ),
      ],
    );
  }
}

// ── POS main content ──────────────────────────────────────────────────────────

class _POSMain extends StatelessWidget {
  final FeatureManager featureManager;
  final _Layout layout;

  const _POSMain({required this.featureManager, required this.layout});

  @override
  Widget build(BuildContext context) {
    final isPortrait = layout == _Layout.phonePortrait ||
        layout == _Layout.tabletPortrait;

    final productArea = Column(
      children: [
        if (layout != _Layout.phonePortrait) const TopBar(),
        if (featureManager.hasFeature('tables')) const TableSelector(),
        const CategoryBar(),
        const Expanded(child: ProductGrid()),
      ],
    );

    if (isPortrait) return productArea;

    final cartWidth =
        layout == _Layout.phoneLandscape ? 260.0 : 340.0;

    return Row(
      children: [
        Expanded(child: productArea),
        SizedBox(
          width: cartWidth,
          child: CartPanel(featureManager: featureManager),
        ),
      ],
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final List<_ScreenEntry> screens;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const _BottomNav({
    required this.screens,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE94560);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: screens.asMap().entries.map((entry) {
              final i = entry.key;
              final screen = entry.value;
              final isActive = activeIndex == i;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? accent.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          screen.icon,
                          size: 22,
                          color: isActive
                              ? accent
                              : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        screen.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isActive
                              ? accent
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Cart FAB ──────────────────────────────────────────────────────────────────

class _CartFAB extends StatelessWidget {
  final int itemCount;
  final VoidCallback onTap;

  const _CartFAB({required this.itemCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F3460),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F3460).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '$itemCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'View Cart',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

// ── Adaptive sidebar (landscape only) ────────────────────────────────────────

class _AdaptiveSidebar extends ConsumerWidget {
  final int activeIndex;
  final List<_ScreenEntry> screens;
  final _Layout layout;
  final ValueChanged<int> onSelect;

  const _AdaptiveSidebar({
    required this.activeIndex,
    required this.screens,
    required this.layout,
    required this.onSelect,
  });

  bool get _compact => layout == _Layout.phoneLandscape;

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content:
            const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
      Navigator.pushNamedAndRemoveUntil(
          context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = _compact;
    final activeStaff = ref.watch(activeStaffProvider);
    const accent = Color(0xFFE94560);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: compact ? 60.0 : 80.0,
      color: const Color(0xFF16213E),
      child: Column(
        children: [
          SizedBox(height: compact ? 12 : 20),

          Container(
            width: compact ? 34 : 44,
            height: compact ? 34 : 44,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(compact ? 9 : 12),
            ),
            child: Icon(Icons.bolt,
                color: Colors.white, size: compact ? 20 : 28),
          ),

          SizedBox(height: compact ? 6 : 12),

          if (activeStaff != null)
            Tooltip(
              message:
                  '${activeStaff.name} (${activeStaff.role.label})',
              child: Container(
                width: compact ? 26 : 36,
                height: compact ? 26 : 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _roleColor(activeStaff.role).withOpacity(0.2),
                  border: Border.all(
                    color:
                        _roleColor(activeStaff.role).withOpacity(0.6),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    activeStaff.name[0].toUpperCase(),
                    style: TextStyle(
                      color: _roleColor(activeStaff.role),
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 10 : 14,
                    ),
                  ),
                ),
              ),
            ),

          SizedBox(height: compact ? 8 : 12),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: screens.asMap().entries.map((entry) {
                  final i = entry.key;
                  final screen = entry.value;
                  final isActive = activeIndex == i;

                  return Tooltip(
                    message: screen.label,
                    child: GestureDetector(
                      onTap: () => onSelect(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.symmetric(
                          vertical: compact ? 2 : 4,
                          horizontal: compact ? 6 : 10,
                        ),
                        padding: EdgeInsets.symmetric(
                            vertical: compact ? 8 : 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? accent.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(compact ? 8 : 10),
                          border: isActive
                              ? Border.all(
                                  color: accent.withOpacity(0.4))
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(screen.icon,
                                color: isActive
                                    ? accent
                                    : Colors.white.withOpacity(0.4),
                                size: compact ? 20 : 24),
                            if (!compact) ...[
                              const SizedBox(height: 4),
                              Text(screen.label,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: isActive
                                          ? accent
                                          : Colors.white
                                              .withOpacity(0.4))),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          Tooltip(
            message: 'Lock',
            child: GestureDetector(
              onTap: () {
                ref.read(activeStaffProvider.notifier).logout();
                ref.read(appLockedProvider.notifier).state = true;
              },
              child: Container(
                margin: EdgeInsets.symmetric(
                    horizontal: compact ? 6 : 10),
                padding: EdgeInsets.symmetric(
                    vertical: compact ? 8 : 10),
                child: Column(children: [
                  Icon(Icons.lock_outline_rounded,
                      color: Colors.white.withOpacity(0.4),
                      size: compact ? 18 : 22),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text('Lock',
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.white.withOpacity(0.4))),
                  ],
                ]),
              ),
            ),
          ),

          Tooltip(
            message: 'Log out',
            child: GestureDetector(
              onTap: () => _logout(context, ref),
              child: Container(
                margin: EdgeInsets.symmetric(
                  vertical: compact ? 4 : 8,
                  horizontal: compact ? 6 : 10,
                ),
                padding: EdgeInsets.symmetric(
                    vertical: compact ? 8 : 10),
                child: Column(children: [
                  Icon(Icons.logout_rounded,
                      color: Colors.white.withOpacity(0.4),
                      size: compact ? 18 : 22),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text('Logout',
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.white.withOpacity(0.4))),
                  ],
                ]),
              ),
            ),
          ),

          SizedBox(height: compact ? 4 : 8),
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

// ── Model ─────────────────────────────────────────────────────────────────────

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