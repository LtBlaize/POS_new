// lib/config/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/role_permissions_provider.dart';
import '../core/providers/staff_provider.dart';
import '../core/providers/admin_provider.dart';               // ADD (Phase 3)
import '../core/models/staff.dart';
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
import '../features/settings/widgets/ip_setup_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/admin/admin_placeholder_screen.dart';     // ADD (Phase 3)
import '../features/admin/admin_shell.dart';                  // ADD (Phase 4)
import '../features/admin/dashboard/admin_dashboard_screen.dart';  // ADD (Phase 4)
import '../features/admin/businesses/admin_businesses_screen.dart';
import '../features/admin/businesses/admin_business_detail_screen.dart';
import '../features/admin/payments/admin_payments_screen.dart';
import '../features/admin/plans/admin_plans_screen.dart';
import '../features/admin/activity/admin_activity_screen.dart';
import '../features/admin/system/admin_system_screen.dart';
import '../features/admin/settings/admin_settings_screen.dart';

// FIX: must be a stable top-level singleton. AppRouter is rebuilt by Riverpod
// every time featureManagerProvider changes (which happens constantly during
// registration as profileProvider/businessProvider refetch). If the
// GlobalKey lived on the AppRouter instance, every rebuild created a NEW key,
// which made MaterialApp treat its Navigator as a brand new widget — tearing
// down the entire navigation stack and resetting to initialRoute ('/pending').
// That's why OTP verification → BusinessTypeScreen would silently bounce
// back to /pending → /login mid-registration.
final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<AppRouter>((ref) {
  final featureManager = ref.watch(featureManagerProvider);
  return AppRouter(featureManager, ref);   // pass ref
});

// Admin routes recognized by the router. Every one of these currently maps
// to a placeholder scaffold (Phase 3) — Phase 4-12 replace them one at a
// time with real screens without touching this list.
const _adminRouteTitles = <String, String>{
  '/admin':               'Admin Dashboard',
  '/admin/dashboard':     'Admin Dashboard',
  '/admin/businesses':    'Businesses',
  '/admin/subscriptions': 'Subscriptions',
  '/admin/payments':      'Payments',
  '/admin/plans':         'Plans',
  '/admin/activity':      'Activity Log',
  '/admin/system':        'System Health',
  '/admin/settings':      'Admin Settings',
};
const _adminBusinessDetailPrefix = '/admin/businesses/';

class AppRouter {
  final FeatureManager? featureManager;
  final Ref _ref;
  GlobalKey<NavigatorState> get navigatorKey => _appNavigatorKey;

  AppRouter(this.featureManager, this._ref);

  // Tab → route mapping for permission checks (existing POS routes only —
  // admin routes are gated separately by _isPlatformAdmin, not staff perms).
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

  /// Returns true if the current session belongs to an active platform
  /// admin. Parallel to _canAccessTab, but reads isPlatformAdminProvider
  /// (Phase 2's is_platform_admin() RPC) instead of staff role permissions —
  /// platform admins are not staff members of any business.
  bool _isPlatformAdmin() {
    return _ref.read(isPlatformAdminProvider).value ?? false;
  }

  bool _isAdminRoute(String name) {
    return _adminRouteTitles.containsKey(name) ||
        name.startsWith(_adminBusinessDetailPrefix);
  }

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name;

    // ── Auth routes (always accessible) ──────────────────────────────────────
    if (name == '/login')         return _route(const LoginScreen());
    if (name == '/register')      return _route(const RegisterScreen());
    if (name == '/business-type') return _route(const BusinessTypeScreen());
    if (name == '/role-select')        return _route(const RoleSelectionScreen());
    if (name == '/forgot-password')    return _route(const ForgotPasswordScreen());

    // /pending is the dedicated boot-wait route. Always serves _PendingPosScreen
    // regardless of featureManager state — it will self-navigate to /admin
    // (Phase 3) or /pos once auth/admin-status/featureManager resolve.
    if (name == '/pending') return _route(const _PendingPosScreen());

    // ── Admin routes ──────────────────────────────────────────────────────────
    // Checked BEFORE the featureManager-null branch below: platform admins
    // have no business, so featureManager will legitimately be null for them
    // forever. Gating on admin status has to happen first or every admin
    // route falls into the "no featureManager yet" POS-pending branch.
    if (name != null && _isAdminRoute(name)) {
      if (!_isPlatformAdmin()) {
        // Not an admin (or admin check hasn't resolved true yet) — never
        // expose even a blank admin scaffold to a non-admin session.
        final user = _ref.read(authStateProvider).value;
        return user != null ? _route(const _PendingPosScreen()) : _route(const LoginScreen());
      }
      // Phase 4: every admin route is now wrapped in AdminShell (sidebar +
      // topbar persist across navigation) instead of a bare placeholder
      // scaffold. The placeholder content itself is unchanged — only what
      // wraps it changed.
      if (name.startsWith(_adminBusinessDetailPrefix)) {
        final id = name.substring(_adminBusinessDetailPrefix.length);
        return _route(AdminShell(
          currentRoute: name,
          child: AdminPlaceholderScreen(title: 'Business Detail: $id'),
        ));
      }
            final title = _adminRouteTitles[name] ?? _adminRouteTitles['/admin']!;
      Widget content;
      if (name == '/admin' || name == '/admin/dashboard') {
        content = const AdminDashboardScreen();
      } else if (name == '/admin/businesses') {
        content = const AdminBusinessesScreen();
      } else if (name.startsWith(_adminBusinessDetailPrefix)) {
        final id = name.substring(_adminBusinessDetailPrefix.length);
        content = AdminBusinessDetailScreen(businessId: id);
      } else if (name == '/admin/payments') {
        content = const AdminPaymentsScreen();
      } else if (name == '/admin/plans') {
        content = const AdminPlansScreen();
      } else if (name == '/admin/activity') {
        content = const AdminActivityScreen();
      } else if (name == '/admin/system') {
        content = const AdminSystemScreen();
      } else if (name == '/admin/settings') {
        content = const AdminSettingsScreen();
      } else {
        content = AdminPlaceholderScreen(title: title);
      }
      
      return _route(AdminShell(currentRoute: name, child: content));
    }

    if (featureManager == null) {
      final user = _ref.read(authStateProvider).value;
      if (user != null) {
        return _route(const _PendingPosScreen());
      }
      return _route(const LoginScreen());
    }

    final fm = featureManager!;

    // ── Feature guards ────────────────────────────────────────────────────────
    final isOwner = _canAccessTab('settings');
    if (!isOwner && name == '/kitchen'   && !fm.hasFeature('kitchen'))   return _pos(fm);
    if (!isOwner && name == '/inventory' && !fm.hasFeature('inventory')) return _pos(fm);
    if (!isOwner && name == '/tables'    && !fm.hasFeature('tables'))    return _pos(fm);
    if (!isOwner && name == '/credits'   && !fm.hasFeature('credits'))   return _pos(fm);
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
      '/ip-setup'  => _route(const IpSetupScreen()),
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
  bool _navigated = false;
  int _nullCount = 0;

  @override
  Widget build(BuildContext context) {
    // ── Admin check, resolved first ──────────────────────────────────────────
    // Per the Phase 3 spec: an admin lands on /admin by default, with an
    // explicit "View as business" affordance elsewhere (Phase 4 shell) rather
    // than silently falling into the normal POS profile flow below. We wait
    // for this to settle (not just "isn't true yet") before touching the
    // profile-based flow, so a slow admin-check can't race a fast profile
    // fetch and flash /pos before correcting to /admin.
    //
    // Tradeoff: this adds the admin-check's round trip to every login, admin
    // or not — see chat note. Acceptable for now; revisit if boot time becomes
    // an issue.
    final adminAsync = ref.watch(isPlatformAdminProvider);

    if (adminAsync.isLoading) {
      return _pendingScaffold;
    }

    final isAdmin = adminAsync.value ?? false;
    if (isAdmin) {
      if (!_navigated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _navigated) return;
          debugPrint('[Pending] platform admin detected → /admin');
          _navigated = true;
          Navigator.pushNamedAndRemoveUntil(context, '/admin', (_) => false);
        });
      }
      return _pendingScaffold;
    }

    // ── Existing POS profile flow (unchanged) ────────────────────────────────
    final profile = ref.watch(profileProvider);

    profile.when(
      data: (p) {
        if (_navigated) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _navigated) return;

          if (p == null) {
            _nullCount++;
            if (_nullCount < 5) {
              debugPrint('[Pending] profile null, retry $_nullCount/5');
              ref.invalidate(profileProvider);
              return;
            }
            debugPrint('[Pending] profile null after retries → /login');
            _navigated = true;
            Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          } else {
            debugPrint('[Pending] profile resolved: ${p.businessId} → /pos');
            _navigated = true;
            Navigator.pushNamedAndRemoveUntil(context, '/pos', (_) => false);
          }
        });
      },
      error: (e, _) {
        if (_navigated) return;
        _navigated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        });
      },
      loading: () {},
    );

    return _pendingScaffold;
  }
}

const _pendingScaffold = Scaffold(
  backgroundColor: Color(0xFF0F1117),
  body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
);