import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/feature_manager.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/business_type_screen.dart';
import '../features/pos/pos_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/kitchen/kitchen_screen.dart';
import '../features/orders/orders_screen.dart';

final appRouterProvider = Provider<AppRouter>((ref) {
  final featureManager = ref.watch(featureManagerProvider);
  return AppRouter(featureManager);
});

class AppRouter {
  final FeatureManager? featureManager;
  AppRouter(this.featureManager);

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name;

    // ── Auth routes (always accessible) ──────────────────────────────────────
    if (name == '/login')         return _route(const LoginScreen());
    if (name == '/register')      return _route(const RegisterScreen());
    if (name == '/business-type') return _route(const BusinessTypeScreen());

    // ── Guard: featureManager not ready → show loading splash ────────────────
    // This happens briefly after registration/login while profileProvider loads.
    // We show a spinner instead of redirecting, so the router re-evaluates
    // once featureManagerProvider emits a value.
    if (featureManager == null) return _route(const _LoadingScreen());

    // ── Guard: feature not enabled → send to /pos ────────────────────────────
    if (name == '/kitchen' && !featureManager!.hasFeature('kitchen')) {
      return _route(POSScreen(featureManager: featureManager!));
    }
    if (name == '/inventory' && !featureManager!.hasFeature('inventory')) {
      return _route(POSScreen(featureManager: featureManager!));
    }

    // ── Protected routes ──────────────────────────────────────────────────────
    return switch (name) {
      '/pos'       => _route(POSScreen(featureManager: featureManager!)),
      '/orders'    => _route(const OrdersScreen()),
      '/kitchen'   => _route(const KitchenScreen()),
      '/inventory' => _route(const InventoryScreen()),
      _            => _route(POSScreen(featureManager: featureManager!)),
    };
  }

  MaterialPageRoute _route(Widget page) =>
      MaterialPageRoute(builder: (_) => page);
}

// Shown briefly while profile/featureManager loads after login or registration.
// MyApp watches appRouterProvider, so once featureManager is ready the user
// will be on /pos via Navigator.pushNamedAndRemoveUntil in BusinessTypeScreen.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F1117),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF6C63FF),
        ),
      ),
    );
  }
}