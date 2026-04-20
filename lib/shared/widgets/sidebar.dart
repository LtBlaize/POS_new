// lib/shared/widgets/sidebar.dart
import 'package:flutter/material.dart';
import '../../core/services/feature_manager.dart';
import 'app_colors.dart';

class SidebarItem {
  final IconData icon;
  final String label;
  final String route;
  final String? requiredFeature;

  const SidebarItem({
    required this.icon,
    required this.label,
    required this.route,
    this.requiredFeature,
  });
}

const _allItems = [
  SidebarItem(icon: Icons.point_of_sale, label: 'POS', route: '/pos'),
  SidebarItem(icon: Icons.receipt_long, label: 'Orders', route: '/orders'),
  SidebarItem(icon: Icons.kitchen, label: 'Kitchen', route: '/kitchen', requiredFeature: 'kitchen'),
  SidebarItem(icon: Icons.table_restaurant, label: 'Tables', route: '/tables', requiredFeature: 'tables'),
  SidebarItem(icon: Icons.inventory_2, label: 'Inventory', route: '/inventory', requiredFeature: 'inventory'),
];

class Sidebar extends StatelessWidget {
  final FeatureManager featureManager;
  final String currentRoute;

  const Sidebar({
    super.key,
    required this.featureManager,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = _allItems.where((item) =>
        item.requiredFeature == null ||
        featureManager.hasFeature(item.requiredFeature!)).toList();

    return Container(
      width: 80,
      color: AppColors.sidebar,
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Logo mark
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
                onTap: () => Navigator.pushReplacementNamed(context, item.route),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.accent.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isActive
                        ? Border.all(color: AppColors.accent.withOpacity(0.4))
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
        ],
      ),
    );
  }
}