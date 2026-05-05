// lib/main.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'config/app_router.dart';
import 'core/providers/lan_orders_notifier.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/lan_client_service.dart';
import 'core/services/lan_server_service.dart';
import 'core/services/local_db_service.dart';
import 'core/services/sync_queue_service.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/register_screen.dart'; // for pendingUserIdProvider

// ── Device role ────────────────────────────────────────────────────────────────
final deviceRoleProvider = StateProvider<DeviceRole>((ref) => DeviceRole.pos);

enum DeviceRole { pos, kitchen }

// ── Entry point ────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await Supabase.initialize(
    url: 'https://qsdbufdixhyqlbygrncp.supabase.co',
    anonKey: 'sb_publishable_IMKcLGls9al71UvjElf_Kw_iC0N4Dqu',
  );

// ✅ ADD THIS: If we have a session but the user no longer exists in DB,
// sign out silently to clear the stale token.
final existingSession = Supabase.instance.client.auth.currentSession;
if (existingSession != null) {
  try {
    // Try to get the user — throws if account was deleted
    final user = await Supabase.instance.client.auth.getUser();
    if (user.user == null) {
      debugPrint('[Boot] Stale session — no user found, signing out');
      await Supabase.instance.client.auth.signOut();
    }
  } catch (e) {
    debugPrint('[Boot] Stale session error ($e) — signing out');
    await Supabase.instance.client.auth.signOut();
  }
}

  final prefs     = await SharedPreferences.getInstance();
  final container = ProviderContainer();

  await container.read(localDbServiceProvider).db;

  final savedRole = prefs.getString('device_role');
  DeviceRole role = DeviceRole.pos;
  if (savedRole != null) {
    role = DeviceRole.values.byNameOrNull(savedRole) ?? DeviceRole.pos;
    container.read(deviceRoleProvider.notifier).state = role;
  }

  final isPos     = savedRole == null || role == DeviceRole.pos;
  final isKitchen = role == DeviceRole.kitchen;

  if (isPos) {
    final businessId = prefs.getString('business_id') ?? '';
    if (businessId.isNotEmpty) {
      await container.read(localDbServiceProvider).clearStaleData(businessId);
    }
  }

  await container.read(connectivityServiceProvider).init();
  container.read(syncQueueServiceProvider).init();

  if (isPos) {
    await container.read(lanServerServiceProvider).start();
    if (!kIsWeb && Platform.isAndroid) await WakelockPlus.enable();
    final ip = await _getLocalIp();
    if (ip != null) {
      await prefs.setString('pos_local_ip', ip);
      debugPrint('[Boot] POS server started — local IP: $ip');
    }
  }

  if (isKitchen) {
    final cachedIp = prefs.getString('cashier_ip');
    if (cachedIp != null && cachedIp.isNotEmpty) {
      container.read(cashierIpProvider.notifier).state = cachedIp;
      final reachable =
          await container.read(connectivityServiceProvider).probeLan(cachedIp);
      if (reachable) {
        final businessId = prefs.getString('business_id') ?? '';
        container.read(kitchenStateProvider.notifier).connect(businessId);
        debugPrint('[Boot] Kitchen — LAN client connected to $cachedIp');
      }
    }
  }

  final String initialRoute =
      Supabase.instance.client.auth.currentSession != null ? '/pos' : '/login';

  debugPrint('[Boot] savedRole: $savedRole  initialRoute: $initialRoute');

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(initialRoute: initialRoute),
    ),
  );
}

// ── Root app ───────────────────────────────────────────────────────────────────

class MyApp extends ConsumerWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // ── Reactive auth listener ─────────────────────────────────────────────
    //
    // Single source of truth for all auth-driven navigation.
    //
    // REGISTRATION GUARD:
    //   During the two-step registration flow, signUp() in step 1 creates
    //   a Supabase session immediately — before the profile row exists in DB.
    //   This listener would fire, try to load the profile (gets null), and
    //   navigate to /pos where featureManager is null → stuck on loading.
    //
    //   The guard: if pendingUserIdProvider is still set, the user is on
    //   BusinessTypeScreen completing step 2. Skip navigation here entirely.
    //   BusinessTypeScreen.completeRegistration() handles its own navigation
    //   after the profile row is written and pendingUserIdProvider is cleared.
    //
    // INTERACTION WITH pos_screen._logout():
    //
    //   pos_screen does an "optimistic logout":
    //     1. Clear local state (cart, activeStaff, appLocked)     — sync
    //     2. Navigator.pushNamedAndRemoveUntil('/login')           — sync, instant
    //     3. authService.logout() fires in background             — async, ~1-3s
    //
    //   When step 3 completes, Supabase fires signedOut →
    //   authStateProvider emits null → this listener also tries to
    //   pushNamedAndRemoveUntil('/login').
    //
    //   We guard against this double-navigation with _isNavigating.
    //   On the signedOut branch we also check if the navigator is
    //   already showing /login to avoid a redundant push.
    //
    bool isNavigating = false;

    ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (previous, next) async {
        final previousUser = previous?.asData?.value;
        final currentUser  = next.asData?.value;

        // No real change in user identity — skip
        if (previousUser?.id == currentUser?.id) return;

        // Guard: only one navigation in flight at a time
        if (isNavigating) return;
        isNavigating = true;

        final nav = router.navigatorKey.currentState;
        if (nav == null) {
          isNavigating = false;
          return;
        }

        try {
          if (currentUser == null) {
            // ── Signed out ─────────────────────────────────────────────────
            //
            // Check if we are already on /login before pushing again.
            // This is the key guard for the pos_screen optimistic logout:
            // pos_screen already pushed /login synchronously, so by the
            // time this listener fires (after the async signOut completes),
            // the top route is already /login — skip the redundant push.
            final isAlreadyOnLogin = nav.canPop() == false &&
                ModalRoute.of(nav.context)?.settings.name == '/login';

            if (!isAlreadyOnLogin) {
              debugPrint('[Auth] Signed out → /login');
              nav.pushNamedAndRemoveUntil('/login', (_) => false);
            } else {
              debugPrint('[Auth] Signed out → already on /login, skipping push');
            }

          } else {
            // ── Signed in ──────────────────────────────────────────────────
            debugPrint('[Auth] Signed in: ${currentUser.id} → checking registration state');

            // ✅ REGISTRATION GUARD: If pendingUserIdProvider is still set,
            // the user just completed step 1 of registration and is currently
            // on BusinessTypeScreen filling out step 2. The profile row does
            // not exist yet in the DB, so profileProvider will return null
            // and featureManager will never resolve. Skip navigation entirely
            // and let BusinessTypeScreen handle it after completeRegistration().
            final isPendingRegistration = ref.read(pendingUserIdProvider) != null;
            if (isPendingRegistration) {
              debugPrint('[Auth] Mid-registration — skipping navigation, waiting for completeRegistration()');
              return;
            }

            debugPrint('[Auth] Signed in: ${currentUser.id} → loading profile');

            try {
              final profile = await ref.read(profileProvider.future);

              if (profile?.business?.id != null) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('business_id', profile!.business!.id);
              }

              final prefs        = await SharedPreferences.getInstance();
              final savedRole    = prefs.getString('device_role');
              final isRestaurant = profile?.businessType?.isRestaurant ?? false;

              if (savedRole == null && isRestaurant) {
                debugPrint('[Auth] Restaurant first launch → /role-select');
                nav.pushNamedAndRemoveUntil('/role-select', (_) => false);
              } else {
                if (savedRole == null) {
                  await prefs.setString('device_role', DeviceRole.pos.name);
                  ref.read(deviceRoleProvider.notifier).state = DeviceRole.pos;
                }
                debugPrint('[Auth] → /pos');
                nav.pushNamedAndRemoveUntil('/pos', (_) => false);
              }
            } catch (e) {
              // Profile fetch failed — go to /pos anyway.
              // _PendingPosScreen will retry once featureManager resolves.
              debugPrint('[Auth] Profile load error: $e — falling back to /pos');
              nav.pushNamedAndRemoveUntil('/pos', (_) => false);
            }
          }
        } finally {
          isNavigating = false;
        }
      },
    );

    // ── Sync toast ─────────────────────────────────────────────────────────
    ref.listen<DateTime?>(syncCompleteProvider, (prev, next) {
      if (next == null) return;
      final ctx = router.navigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('All changes synced to server'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    });

    return MaterialApp(
      title: 'POS System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F3460)),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      navigatorKey: router.navigatorKey,
      initialRoute: initialRoute,
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Future<String?> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (e) {
    debugPrint('[Boot] Could not determine local IP: $e');
  }
  return null;
}

extension _EnumByNameOrNull<T extends Enum> on Iterable<T> {
  T? byNameOrNull(String name) {
    for (final v in this) {
      if (v.name == name) return v;
    }
    return null;
  }
}

Future<void> savePosIp(String ip, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('cashier_ip', ip);
  ref.read(cashierIpProvider.notifier).state = ip;
  debugPrint('[Settings] POS IP saved: $ip');
}

Future<String?> readPosLocalIp() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('pos_local_ip');
}