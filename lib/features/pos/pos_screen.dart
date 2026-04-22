// lib/features/pos/pos_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/feature_manager.dart';
import '../../features/auth/auth_provider.dart';

import '../inventory/inventory_screen.dart';
import '../kitchen/kitchen_screen.dart';
import '../orders/orders_screen.dart';
import '../tables/table_selector.dart';

import 'widgets/product/product_grid.dart';
import 'widgets/cart_panel.dart';
import 'widgets/layout/top_bar.dart';
import 'widgets/category_bar.dart';

final _activeIndexProvider = StateProvider<int>((ref) => 0);

class POSScreen extends ConsumerWidget {
  final FeatureManager featureManager;

  const POSScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = ref.watch(_activeIndexProvider);
    final screens = _buildScreens(featureManager);

    return Scaffold(
      body: Row(
        children: [
          _AdaptiveSidebar(
            featureManager: featureManager,
            activeIndex: activeIndex,
            screens: screens,
            onSelect: (i) =>
                ref.read(_activeIndexProvider.notifier).state = i,
          ),
          Expanded(
            child: IndexedStack(
              index: activeIndex,
              children: screens.map((s) => s.widget).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<_ScreenEntry> _buildScreens(FeatureManager fm) {
    return [
      _ScreenEntry(
        icon: Icons.point_of_sale_rounded,
        label: 'POS',
        widget: _POSMain(featureManager: fm),
      ),
      _ScreenEntry(
        icon: Icons.receipt_long_rounded,
        label: 'Orders',
        widget: OrdersScreen(featureManager: fm),
      ),
      if (fm.hasFeature('kitchen'))
        _ScreenEntry(
          icon: Icons.kitchen_rounded,
          label: 'Kitchen',
          widget: const KitchenScreen(),
        ),
      if (fm.hasFeature('inventory'))
        _ScreenEntry(
          icon: Icons.inventory_2_rounded,
          label: 'Inventory',
          widget: const InventoryScreen(),
        ),
    ];
  }
}

// ── POS MAIN ─────────────────────────────────────────────

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

// ── SIDEBAR ─────────────────────────────────────────────

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

    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 80,
      color: const Color(0xFF16213E),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Logo
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE94560),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 28),
          ),

          const SizedBox(height: 24),

          // Nav items
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
                  margin:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFE94560).withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isActive
                        ? Border.all(
                            color:
                                const Color(0xFFE94560).withOpacity(0.4))
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

          const Spacer(),

          // Logout
          Tooltip(
            message: 'Log out',
            child: GestureDetector(
              onTap: () => _logout(context, ref),
              child: Container(
                margin:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(Icons.logout_rounded,
                        color: Colors.white.withOpacity(0.4)),
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
        ],
      ),
    );
  }
}

// ── MODEL ─────────────────────────────────────────────

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