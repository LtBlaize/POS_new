// lib/features/pos/pos_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/staff.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/product_provider.dart';
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
import 'widgets/product/promo_grid.dart';
import '../../core/providers/shift_provider.dart';
import '../../features/shifts/close_shift_screen.dart';
import '../../shared/widgets/app_colors.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:collection/collection.dart';
import '../../core/models/product.dart';

// Scoped to the active business so switching businesses resets the tab.
// Watches profileProvider so it invalidates automatically on business change.
final _activeIndexProvider = StateProvider<int>((ref) {
  // Depend on businessId — when it changes, this provider resets to 0.
  ref.watch(profileProvider.select((p) => p.asData?.value?.businessId));
  return 0;
});

// ── Layout mode ───────────────────────────────────────────────────────────────

enum _Layout {
  phonePortrait,
  phoneLandscape,
  tabletPortrait,
  tabletLandscape,
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
    final allowedTabs = ref.watch(activeStaffTabsProvider);
    final activeStaff = ref.watch(activeStaffProvider);
    // Re-read live from the provider instead of trusting the constructor
    // value — featureManager passed in at route-push time can be stale
    // if featureConfigProvider (enable_kitchen_display etc.) hadn't
    // resolved yet when /pos was first navigated to.
    final fm = ref.watch(featureManagerProvider);

    final screens = _buildScreens(
      fm,
      activeStaff?.role ?? StaffRole.cashier,
      allowedTabs,
      layout,
    );

    final safeIndex =
        screens.isEmpty ? 0 : activeIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: PinLockOverlay(
        child: switch (layout) {
          _Layout.phonePortrait || _Layout.tabletPortrait => _PortraitShell(
              featureManager: fm,
              screens: screens,
              activeIndex: safeIndex,
              layout: layout,
              onSelect: (i) {
                ref.read(_activeIndexProvider.notifier).state = i;
                ref.read(posSearchQueryProvider.notifier).state = '';
              },
            ),
          _Layout.phoneLandscape || _Layout.tabletLandscape => _LandscapeShell(
              featureManager: fm,
              screens: screens,
              activeIndex: safeIndex,
              layout: layout,
                onSelect: (i) {
                ref.read(_activeIndexProvider.notifier).state = i;
                ref.read(posSearchQueryProvider.notifier).state = '';
              },
          ),
        },
      ),
    );
  }

  List<_ScreenEntry> _buildScreens(
    FeatureManager fm,
    StaffRole role,
    Set<String> allowedTabs,
    _Layout layout,
  ) {
    bool allowed(String tab) => allowedTabs.contains(tab);

    return [
      if (allowed('pos'))
        _ScreenEntry(
          icon: Icons.point_of_sale_rounded,
          label: 'POS',
          widget: _POSMain(featureManager: fm, layout: layout),
        ),
      if (allowed('orders'))
        _ScreenEntry(
          icon: Icons.receipt_long_rounded,
          label: 'Orders',
          widget: OrdersScreen(featureManager: fm),
        ),
      if (allowed('kitchen') && fm.hasFeature('kitchen'))
        _ScreenEntry(
          icon: Icons.kitchen_rounded,
          label: 'Kitchen',
          widget: const KitchenScreen(),
        ),
      if (allowed('inventory') && fm.hasFeature('inventory'))
        _ScreenEntry(
          icon: Icons.inventory_2_rounded,
          label: 'Inventory',
          widget: const InventoryScreen(),
        ),
      if (allowed('utang') && fm.hasFeature('credits'))
        _ScreenEntry(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Utang',
          widget: CreditsScreen(featureManager: fm),
        ),
      if (allowed('reports'))
        _ScreenEntry(
          icon: Icons.bar_chart_rounded,
          label: 'Reports',
          widget: ReportsScreen(featureManager: fm),
        ),
      if (allowed('settings'))
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomNav(
        screens: screens,
        activeIndex: activeIndex,
        onSelect: onSelect,
        onLock: () {
          ref.read(activeStaffProvider.notifier).logout();
          ref.read(appLockedProvider.notifier).state = true;
        },
        onLogout: () => _doLogout(context, ref),
      ),
    );
  }

  Future<void> _doLogout(BuildContext context, WidgetRef ref) async {
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

    ref.read(cartProvider.notifier).clear();
    ref.read(activeStaffProvider.notifier).logout();
    ref.read(appLockedProvider.notifier).state = true;

    try {
      await ref.read(authServiceProvider).logout();
      // Navigation to /login is handled by MyApp's authStateProvider listener.
      // Do NOT navigate here — double navigation crashes the widget tree.
    } catch (e) {
      debugPrint('[Logout] signOut error (continuing): $e');
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    }
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              Expanded(child: CartPanel(featureManager: featureManager)),
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

class _POSMain extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final _Layout layout;

  const _POSMain({required this.featureManager, required this.layout});

  @override
  ConsumerState<_POSMain> createState() => _POSMainState();
}

class _POSMainState extends ConsumerState<_POSMain> {
  final _barcodeBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // If a text field has focus, let all keystrokes through unmodified.
    // Hardware barcode scanners are not used when typing in search/input fields.
    final focus = FocusManager.instance.primaryFocus;
    final isTextField = focus?.context?.widget is EditableText;
    if (isTextField) return false;

    final now = DateTime.now();
    final gap = now.difference(_lastKeyTime).inMilliseconds;
    _lastKeyTime = now;

    if (gap > 100) _barcodeBuffer.clear();

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final barcode = _barcodeBuffer.toString().trim();
      _barcodeBuffer.clear();
      if (barcode.isNotEmpty) _handleBarcode(barcode);
      return barcode.isNotEmpty; // only consume if we actually handled a barcode
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      // Only buffer if characters are arriving fast (scanner cadence < 100ms).
      // Slow typing (gap >= 50ms) is a human — don't consume.
      if (gap < 50 || _barcodeBuffer.isNotEmpty) {
        _barcodeBuffer.write(char);
        return true;
      }
    }

    return false;
  }

  void _handleBarcode(String barcode) {
    final products = ref.read(productListProvider).asData?.value ?? [];
    final match = products.firstWhereOrNull(
      (p) => (p.barcode == barcode || p.sku == barcode) && p.isActive,
    );
    _showBarcodeResult(match, barcode);
  }

  void _showBarcodeResult(Product? match, String barcode) {
    if (!mounted) return;

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No product found for barcode: $barcode'),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 2),
      ));
      return;
    }

    if (match.trackInventory && match.stockQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${match.name} is out of stock.'),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 2),
      ));
      return;
    }

    ref.read(cartProvider.notifier).addProduct(match);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${match.name} added to cart'),
      backgroundColor: AppColors.success,
      duration: const Duration(milliseconds: 800),
    ));
  }

  void _openCameraScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BarcodeScannerSheet(
        onDetect: (barcode) {
          Navigator.pop(context);
          _handleBarcode(barcode);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = widget.layout == _Layout.phonePortrait ||
        widget.layout == _Layout.tabletPortrait;

    final productArea = Column(
      children: [
        if (widget.layout == _Layout.phonePortrait)
          _PhoneSearchBar(onCameraTap: _openCameraScanner)
        else
          TopBar(onCameraTap: _openCameraScanner),
        const TrialBanner(),
        if (widget.featureManager.hasFeature('tables')) const TableSelector(),
        const CategoryBar(),
        Expanded(
          child: ref.watch(posViewModeProvider) == PosViewMode.promos
              ? const PromoGrid()
              : const ProductGrid(),
        ),
      ],
    );

    if (isPortrait) return productArea;

    final cartWidth = widget.layout == _Layout.phoneLandscape ? 260.0 : 340.0;

    return Row(
      children: [
        Expanded(child: productArea),
        SizedBox(
          width: cartWidth,
          child: CartPanel(featureManager: widget.featureManager),
        ),
      ],
    );
  }
}

// ── Camera scanner sheet ──────────────────────────────────────────────────────

class _BarcodeScannerSheet extends StatefulWidget {
  final ValueChanged<String> onDetect;
  const _BarcodeScannerSheet({required this.onDetect});

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.55,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Scan Barcode or QR Code',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  if (_handled) return;
                  final code = capture.barcodes.firstOrNull?.rawValue;
                  if (code != null && code.isNotEmpty) {
                    _handled = true;
                    widget.onDetect(code);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phone search bar ──────────────────────────────────────────────────────────

class _PhoneSearchBar extends ConsumerStatefulWidget {
  final VoidCallback onCameraTap;
  const _PhoneSearchBar({required this.onCameraTap});

  @override
  ConsumerState<_PhoneSearchBar> createState() => _PhoneSearchBarState();
}

class _PhoneSearchBarState extends ConsumerState<_PhoneSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // rebuild to show/hide clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      ref.read(posSearchQueryProvider.notifier).state = v;
    });
  }

  void _clear() {
    _controller.clear();
    setState(() {});
    _debounce?.cancel();
    ref.read(posSearchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search products or scan barcode…',
                  hintStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha:0.7),
                      fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              GestureDetector(
                onTap: _clear,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                ),
              )
            else
              GestureDetector(
                onTap: widget.onCameraTap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.qr_code_scanner_rounded,
                      size: 16, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


// ── Bottom nav ────────────────────────────────────────────────────────────────

class _BottomNav extends ConsumerWidget {
  final List<_ScreenEntry> screens;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLock;
  final VoidCallback onLogout;

  const _BottomNav({
    required this.screens,
    required this.activeIndex,
    required this.onSelect,
    required this.onLock,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accent = Color(0xFFE94560);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.06),
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
            children: [
              ...screens.asMap().entries.map((entry) {
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
                                ? accent.withValues(alpha:0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            screen.icon,
                            size: 22,
                            color: isActive ? accent : Colors.grey.shade400,
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
                            color: isActive ? accent : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              // ── Divider ───────────────────────────────────────────────
              Container(
                width: 1,
                height: 32,
                color: Colors.grey.shade200,
                margin: const EdgeInsets.symmetric(horizontal: 2),
              ),

              // ── Lock ──────────────────────────────────────────────────
              GestureDetector(
                onTap: onLock,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 20, color: Colors.grey.shade400),
                      const SizedBox(height: 2),
                      Text('Lock',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ),

              // ── Logout ────────────────────────────────────────────────
              if (ref.watch(activeStaffTabsProvider).contains('settings'))
              GestureDetector(
                onTap: onLogout,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded,
                          size: 20, color: Colors.grey.shade400),
                      const SizedBox(height: 2),
                      Text('Logout',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 4),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F3460),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F3460).withValues(alpha:0.35),
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
                color: Colors.white.withValues(alpha:0.2),
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

    // Clear local state first
    ref.read(cartProvider.notifier).clear();
    ref.read(activeStaffProvider.notifier).logout();
    ref.read(appLockedProvider.notifier).state = true;

    try {
      await ref.read(authServiceProvider).logout();
      // Navigation to /login is handled by MyApp's authStateProvider listener.
      // Do NOT navigate here — double navigation crashes the widget tree.
    } catch (e) {
      debugPrint('[Logout] signOut error (continuing): $e');
      // If signOut fails, navigate manually as fallback
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    }
  }

  void _showCloseShift(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloseShiftScreen(
          onShiftClosed: () {
            ref.read(activeStaffProvider.notifier).logout();
            ref.read(appLockedProvider.notifier).state = true;
            Navigator.pushNamedAndRemoveUntil(context, '/pos', (_) => false);
          },
          onCancel: () => Navigator.pop(context),
        ),
      ),
    );
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
              message: '${activeStaff.name} (${activeStaff.role.label})',
              child: Container(
                width: compact ? 26 : 36,
                height: compact ? 26 : 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _roleColor(activeStaff.role).withValues(alpha:0.2),
                  border: Border.all(
                    color: _roleColor(activeStaff.role).withValues(alpha:0.6),
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
                              ? accent.withValues(alpha:0.15)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(compact ? 8 : 10),
                          border: isActive
                              ? Border.all(color: accent.withValues(alpha:0.4))
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              screen.icon,
                              color: isActive
                                  ? accent
                                  : Colors.white.withValues(alpha:0.4),
                              size: compact ? 20 : 24,
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 4),
                              Text(
                                screen.label,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isActive
                                      ? accent
                                      : Colors.white.withValues(alpha:0.4),
                                ),
                              ),
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

          Consumer(
            builder: (context, ref, _) {
              final shift = ref.watch(currentShiftProvider).value;
              if (shift == null) return const SizedBox.shrink();
              return Tooltip(
                message: 'Close Shift',
                child: GestureDetector(
                  onTap: () => _showCloseShift(context, ref),
                  child: Container(
                    margin: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 10),
                    padding: EdgeInsets.symmetric(
                        vertical: compact ? 8 : 10),
                    child: Column(children: [
                      Icon(
                        Icons.lock_clock_outlined,
                        color: const Color(0xFFE94560).withValues(alpha:0.8),
                        size: compact ? 18 : 22,
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 9,
                            color: const Color(0xFFE94560).withValues(alpha:0.8),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              );
            },
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
                margin: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
                child: Column(children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white.withValues(alpha:0.4),
                    size: compact ? 18 : 22,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Lock',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha:0.4),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),

          if (ref.watch(activeStaffTabsProvider).contains('settings'))
          Tooltip(
            message: 'Log out',
            child: GestureDetector(
              onTap: () => _logout(context, ref),
              child: Container(
                margin: EdgeInsets.symmetric(
                  vertical: compact ? 4 : 8,
                  horizontal: compact ? 6 : 10,
                ),
                padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
                child: Column(children: [
                  Icon(
                    Icons.logout_rounded,
                    color: Colors.white.withValues(alpha:0.4),
                    size: compact ? 18 : 22,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha:0.4),
                      ),
                    ),
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
        StaffRole.owner   => const Color(0xFFE94560),
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