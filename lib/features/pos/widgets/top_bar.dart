// lib/features/pos/widgets/top_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../shared/widgets/app_colors.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final itemCount = cartItems.fold(0, (sum, i) => sum + i.quantity);
    final now = DateTime.now();
    final timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateLabel =
        '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Date + time
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeLabel,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Search bar
          Container(
            width: 280,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search products or scan barcode…',
                      hintStyle: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.7),
                          fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('⌘K',
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Cart badge
          _IconBadge(
            icon: Icons.shopping_cart_outlined,
            count: itemCount,
            color: AppColors.primary,
          ),

          const SizedBox(width: 8),

          // Notifications
          _IconBadge(
            icon: Icons.notifications_outlined,
            count: 0,
            color: AppColors.warning,
          ),

          const SizedBox(width: 16),

          // Cashier avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, Color(0xFFFF7B54)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('CJ',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(int d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];

  String _month(int m) => [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;

  const _IconBadge(
      {required this.icon, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}