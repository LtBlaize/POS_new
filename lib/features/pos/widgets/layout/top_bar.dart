// lib/features/pos/widgets/layout/top_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/cart_provider.dart';
import '../../../../shared/widgets/app_colors.dart';

// Matches pos_screen.dart breakpoint
const _kBreakpointSm = 900.0;

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < _kBreakpointSm;

    final cartItems = ref.watch(cartProvider);
    final itemCount = cartItems.fold(0, (sum, i) => sum + i.quantity);
    final now = DateTime.now();
    final timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateLabel =
        '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';

    return Container(
      height: isCompact ? 52 : 64,
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
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20),
      child: Row(
        children: [
          // Date + time — hide date on compact, keep time
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeLabel,
                style: TextStyle(
                  fontSize: isCompact ? 16 : 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              if (!isCompact)
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

          // Search bar — narrower on compact
          Container(
            width: isCompact ? 180 : 280,
            height: isCompact ? 32 : 38,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                SizedBox(width: isCompact ? 8 : 10),
                Icon(Icons.search,
                    size: isCompact ? 15 : 18,
                    color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    style: TextStyle(fontSize: isCompact ? 12 : 13),
                    decoration: InputDecoration(
                      hintText: isCompact
                          ? 'Search…'
                          : 'Search products or scan barcode…',
                      hintStyle: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.7),
                          fontSize: isCompact ? 12 : 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                // Hide keyboard shortcut hint on compact
                if (!isCompact)
                  Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('⌘K',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),

          SizedBox(width: isCompact ? 8 : 16),

          // Cart badge
          _IconBadge(
            icon: Icons.shopping_cart_outlined,
            count: itemCount,
            color: AppColors.primary,
            compact: isCompact,
          ),

          SizedBox(width: isCompact ? 4 : 8),

          // Notifications — hide on very compact to save space
          if (!isCompact)
            _IconBadge(
              icon: Icons.notifications_outlined,
              count: 0,
              color: AppColors.warning,
              compact: false,
            ),

          SizedBox(width: isCompact ? 8 : 16),

          // Cashier avatar
          Container(
            width: isCompact ? 30 : 36,
            height: isCompact ? 30 : 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, Color(0xFFFF7B54)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.circular(isCompact ? 8 : 10),
            ),
            child: Center(
              child: Text('CJ',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 10 : 12,
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
  final bool compact;

  const _IconBadge({
    required this.icon,
    required this.count,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 38.0;
    final iconSize = compact ? 16.0 : 20.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(compact ? 8 : 10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Icon(icon, size: iconSize, color: AppColors.textSecondary),
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
              constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
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