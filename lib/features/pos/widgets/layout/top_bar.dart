// lib/features/pos/widgets/layout/top_bar.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/app_colors.dart';
import '../../../../core/providers/product_provider.dart';
import '../../../../features/auth/auth_provider.dart';
import '../../../../core/providers/role_permissions_provider.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/thermal_print_service.dart';
import '../../../../features/auth/manager_override_dialog.dart';

// Matches pos_screen.dart breakpoint
const _kBreakpointSm = 900.0;

/// One row in the low-stock list: a plain product, or one variant of a product.
class LowStockEntry {
  final String name;
  final int stock;
  const LowStockEntry(this.name, this.stock);
}

/// Active, stock-tracked items at or below the low-stock threshold, lowest
/// first. Products with variants are listed per variant ("Product · Variant").
final lowStockProvider = Provider<List<LowStockEntry>>((ref) {
  final products = ref.watch(productListProvider).asData?.value ?? [];
  final cfg = ref.watch(featureConfigProvider).value;
  final threshold = (cfg?['low_stock_threshold'] as num?)?.toInt() ?? 5;

  final out = <LowStockEntry>[];
  for (final p in products) {
    if (!p.isActive || !p.trackInventory) continue;
    if (p.hasVariants) {
      for (final v in p.activeVariants) {
        if (v.stockQuantity <= threshold) {
          out.add(LowStockEntry('${p.name} · ${v.name}', v.stockQuantity));
        }
      }
    } else if (p.stockQuantity <= threshold) {
      out.add(LowStockEntry(p.name, p.stockQuantity));
    }
  }
  out.sort((a, b) => a.stock.compareTo(b.stock));
  return out;
});

/// Set to a tab label (e.g. 'Inventory') to ask POSScreen to switch to it.
/// POSScreen resets it to null after handling.
final posRequestedTabProvider = StateProvider<String?>((ref) => null);

// Change class declarationn
class TopBar extends ConsumerWidget {
  final VoidCallback? onCameraTap;
  const TopBar({super.key, this.onCameraTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < _kBreakpointSm;


    final businessName = ref.watch(businessProvider)?.name ?? '';
    final initials = _initials(businessName);
    final now = DateTime.now();
    final timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateLabel =
        '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';

    return Container(
      height: isCompact ? 52 : 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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

          // Search bar
          _SearchField(compact: isCompact, onCameraTap: onCameraTap),

          SizedBox(width: isCompact ? 8 : 16),

// Open cash drawer (manager PIN required)
          _DrawerButton(compact: isCompact),

          SizedBox(width: isCompact ? 4 : 8),



          // Notifications — hide on very compact to save space
          if (!isCompact)
            Builder(
              builder: (context) {
                final lowStock = ref.watch(lowStockProvider);
                return GestureDetector(
                  onTap: () => _showLowStock(context, ref, lowStock),
                  child: _IconBadge(
                    icon: Icons.notifications_outlined,
                    count: lowStock.length,
                    color: AppColors.warning,
                    compact: false,
                  ),
                );
              },
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
              borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isCompact ? 10 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // "Flux Point" -> FP, "Blaize Catering" -> BC, "Fluxpoint" -> FL
  String _initials(String name) {
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  void _showLowStock(
    BuildContext context,
    WidgetRef ref,
    List<LowStockEntry> items,
  ) {
    final fm = ref.read(featureManagerProvider);
    final canOpenInventory =
        ref.read(activeStaffTabsProvider).contains('inventory') &&
        fm.hasFeature('inventory');

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Low stock'),
            content: SizedBox(
              width: 340,
              child:
                  items.isEmpty
                      ? const Text(
                        'All stocked items are above the low-stock level.',
                      )
                      : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in items)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(e.name),
                              trailing: Text(
                                e.stock <= 0
                                    ? 'Out of stock'
                                    : '${e.stock} left',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color:
                                      e.stock <= 0
                                          ? Colors.red
                                          : AppColors.warning,
                                ),
                              ),
                            ),
                        ],
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              if (canOpenInventory)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ref.read(posRequestedTabProvider.notifier).state =
                        'Inventory';
                  },
                  child: const Text('Go to Inventory'),
                ),
            ],
          ),
    );
  }

  String _weekday(int d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];

  String _month(int m) =>
      [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][m - 1];
}

class _SearchField extends ConsumerStatefulWidget {
  final bool compact;
  final VoidCallback? onCameraTap;
  const _SearchField({required this.compact, this.onCameraTap});

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // show/hide the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      ref.read(posSearchQueryProvider.notifier).state = v;
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {});
    ref.read(posSearchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;

    // If something else clears the query (category tap, tab switch),
    // clear the visible text too so the box never lies.
    ref.listen<String>(posSearchQueryProvider, (_, next) {
      if (next.isEmpty && _controller.text.isNotEmpty) {
        _debounce?.cancel();
        _controller.clear();
        setState(() {});
      }
    });

    return Container(
      width: compact ? 180 : 300,
      height: compact ? 32 : 38,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          SizedBox(width: compact ? 8 : 10),
          Icon(
            Icons.search,
            size: compact ? 15 : 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              style: TextStyle(fontSize: compact ? 12 : 13),
              decoration: InputDecoration(
                hintText:
                    compact ? 'Search…' : 'Search products or scan barcode…',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                  fontSize: compact ? 12 : 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: _clear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.close,
                  size: compact ? 15 : 17,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else if (widget.onCameraTap != null)
            GestureDetector(
              onTap: widget.onCameraTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: compact ? 16 : 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Cash drawer button ────────────────────────────────────────────────────────

class _DrawerButton extends ConsumerWidget {
  final bool compact;
  const _DrawerButton({required this.compact});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // Grab these before the await so we never touch ref after disposal.
    final audit = ref.read(auditServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    final approver = await requireManagerOverride(
      context: context,
      ref: ref,
      action: 'Open Cash Drawer (No Sale)',
    );
    if (approver == null) return;

    final ok = await ThermalPrintService.openCashDrawer();

    await audit.log(
      actionType: AuditAction.drawerOpenNoSale,
      description:
          ok
              ? 'Cash drawer opened (no sale)'
              : 'Cash drawer open FAILED (no sale)',
      authorisedBy: approver,
      metadata: {'success': ok},
    );

    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open drawer. Check the printer connection in Settings.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = compact ? 32.0 : 38.0;
    return Tooltip(
      message: 'Open cash drawer',
      child: GestureDetector(
        onTap: () => _open(context, ref),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(compact ? 8 : 10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Icon(
            Icons.point_of_sale,
            size: compact ? 16 : 20,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Trial banner ──────────────────────────────────────────────────────────────

class TrialBanner extends ConsumerWidget {
  const TrialBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fm = ref.watch(featureManagerProvider);

    final days = fm.trialDaysLeft;
    final isExpired = !fm.isOnActiveTrial && !fm.currentPlan.isPaid;

    // Hide banner entirely if paid or trial hasn't started yet.
    if (fm.currentPlan.isPaid ||
        fm.isOnActiveTrial == false && days == 0 && !isExpired) {
      return const SizedBox.shrink();
    }

    final Color bg;
    final Color fg;
    final String message;

    if (isExpired) {
      bg = const Color(0xFFFFEBEB);
      fg = const Color(0xFFC0392B);
      message = 'Your trial has expired — upgrade to keep full access.';
    } else if (days <= 1) {
      bg = const Color(0xFFFFEBEB);
      fg = const Color(0xFFC0392B);
      message = 'Last day of your trial — upgrade now to avoid losing access.';
    } else if (days <= 2) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFE65100);
      message = '$days days left in your trial — upgrade to keep full access.';
    } else {
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFF856404);
      message = '$days days left in your free trial.';
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.access_time_rounded, size: 14, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _openUpgrade(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: fg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Upgrade',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openUpgrade(BuildContext context) {
    // Phase 8 will wire this to the settings upgrade screen.
    // For now show a snackbar as a placeholder.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upgrade coming soon — check Settings.')),
    );
  }
}
