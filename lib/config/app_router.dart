// lib/config/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/role_permissions_provider.dart';   // ADD
import '../core/providers/staff_provider.dart';              // ADD
import '../core/models/staff.dart';                          // ADD
import '../core/services/feature_manager.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/business_type_screen.dart';
import '../features/pos/pos_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/kitchen/kitchen_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/credits/credits_screen.dart';
import '../features/auth/role_selection_screen.dart';
import '../features/settings/settings_screen.dart';

final appRouterProvider = Provider<AppRouter>((ref) {
  final featureManager = ref.watch(featureManagerProvider);
  return AppRouter(featureManager, ref);   // pass ref
});

class AppRouter {
  final FeatureManager? featureManager;
  final Ref _ref;                          // ADD
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  AppRouter(this.featureManager, this._ref);   // ADD _ref

  // Tab → route mapping for permission checks
  static const _tabForRoute = <String, String>{
    '/pos':       'pos',
    '/orders':    'orders',
    '/kitchen':   'kitchen',
    '/tables':    'kitchen',
    '/inventory': 'inventory',
    '/credits':   'utang',
    '/reports':   'reports',
    '/settings':  'settings',
  };

  /// Returns true if the currently active staff member can access [tab].
  bool _canAccessTab(String tab) {
    final staff = _ref.read(activeStaffProvider);
    if (staff == null) return false;
    if (staff.role == StaffRole.owner) return true;   // owner always can

    final perms = _ref.read(rolePermissionsProvider).value ?? {};
    return perms[staff.role.value]?.contains(tab) ?? false;
  }

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name;

    // ── Auth routes (always accessible) ──────────────────────────────────────
    if (name == '/login')         return _route(const LoginScreen());
    if (name == '/register')      return _route(const RegisterScreen());
    if (name == '/business-type') return _route(const BusinessTypeScreen());
    if (name == '/role-select')   return _route(const RoleSelectionScreen());

    if (featureManager == null) {
      final user = _ref.read(authStateProvider).value;
      if (user != null) {
        return _route(const _PendingPosScreen());
      }
      return _route(const LoginScreen());
    }

    final fm = featureManager!;

    // ── Feature guards ────────────────────────────────────────────────────────
    if (name == '/kitchen'   && !fm.hasFeature('kitchen'))   return _pos(fm);
    if (name == '/inventory' && !fm.hasFeature('inventory')) return _pos(fm);
    if (name == '/tables'    && !fm.hasFeature('tables'))    return _pos(fm);
    if (name == '/credits'   && !fm.hasFeature('credits'))   return _pos(fm);

    // ── Tab permission guards ─────────────────────────────────────────────────
    final requiredTab = _tabForRoute[name];
    if (requiredTab != null && !_canAccessTab(requiredTab)) {
      return _pos(fm);
    }

    // ── Protected routes ──────────────────────────────────────────────────────
    return switch (name) {
      '/pos'       => _route(POSScreen(featureManager: fm)),
      '/orders'    => _route(OrdersScreen(featureManager: fm)),
      '/kitchen'   => _route(const KitchenScreen()),
      '/inventory' => _route(const InventoryScreen()),
      '/settings'  => _route(SettingsScreen(featureManager: fm)),
      '/credits'   => _route(CreditsScreen(featureManager: fm)),
      _            => _pos(fm),
    };
  }

  MaterialPageRoute _route(Widget page) =>
      MaterialPageRoute(builder: (_) => page);

  MaterialPageRoute _pos(FeatureManager fm) =>
      _route(POSScreen(featureManager: fm));
}

class _PendingPosScreen extends ConsumerStatefulWidget {
  const _PendingPosScreen();
  @override
  ConsumerState<_PendingPosScreen> createState() => _PendingPosScreenState();
}

class _PendingPosScreenState extends ConsumerState<_PendingPosScreen> {
  bool _navigated = false; // ← fires exactly once

  @override
  Widget build(BuildContext context) {
    final featureManager = ref.watch(featureManagerProvider);

    if (featureManager != null && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/pos', (_) => false);
        }
      });
    }

    return const Scaffold(
      backgroundColor: Color(0xFF0F1117),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
    );
  }
}
