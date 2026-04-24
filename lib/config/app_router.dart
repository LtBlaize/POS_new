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
import '../features/credits/credits_screen.dart'; // ← ADD

final appRouterProvider = Provider<AppRouter>((ref) {
  final featureManager = ref.watch(featureManagerProvider);
  return AppRouter(featureManager);
});

class AppRouter {
  final FeatureManager? featureManager;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  AppRouter(this.featureManager);

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name;

    // ── Auth routes (always accessible) ──────────────────────────────────────
    if (name == '/login')         return _route(const LoginScreen());
    if (name == '/register')      return _route(const RegisterScreen());
    if (name == '/business-type') return _route(const BusinessTypeScreen());

    if (featureManager == null) {
      return _route(const _PendingPosScreen());
    }

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
      '/orders'    => _route(OrdersScreen(featureManager: featureManager!)),
      '/kitchen'   => _route(const KitchenScreen()),
      '/inventory' => _route(const InventoryScreen()),
      '/credits'   => _route(CreditsScreen(featureManager: featureManager!)), // ← ADD
      _            => _route(POSScreen(featureManager: featureManager!)),
    };
  }

  MaterialPageRoute _route(Widget page) =>
      MaterialPageRoute(builder: (_) => page);
}

class _PendingPosScreen extends ConsumerWidget {
  const _PendingPosScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featureManager = ref.watch(featureManagerProvider);

    if (featureManager != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/pos',
            (_) => false,
          );
        }
      });
    }

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