// lib/main.dart
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  await dotenv.load(fileName: 'assets/.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );

  // FIX 1: Only sign out on real auth errors (deleted account, revoked token).
  // Previously this caught ALL exceptions including network timeouts, which
  // caused the app to sign out users whenever the device was offline at boot.
  

final existingSession = Supabase.instance.client.auth.currentSession;
if (existingSession != null) {
    try {
      await Supabase.instance.client.auth.refreshSession();
      debugPrint('[Boot] Session refreshed successfully');
    } on AuthException catch (e) {
      debugPrint('[Boot] Auth error ($e) — signing out');
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('[Boot] Network error during refresh ($e) — keeping session');
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
    final savedKey = prefs.getString('pos_lan_key');
    if (savedKey != null && savedKey.isNotEmpty) {
      LanServerService.setPosKey(savedKey);
    } else {
      final newKey = LanServerService.getPosKey(); // generates one
      await prefs.setString('pos_lan_key', newKey);
    }
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

  // Always boot to /pending when a session exists.
  // _PendingPosScreen watches featureManagerProvider and navigates to /pos
  // once it resolves — eliminating the race between initialRoute and
  // featureManagerProvider being null on the first frame.
  final String initialRoute =
      Supabase.instance.client.auth.currentSession != null ? '/pending' : '/login';

  debugPrint('[Boot] savedRole: $savedRole  initialRoute: $initialRoute');

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(initialRoute: initialRoute),
    ),
  );
}

// ── Root app ───────────────────────────────────────────────────────────────────

class MyApp extends ConsumerStatefulWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _initialEventSkipped = false;
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) async {
      if (!_initialEventSkipped) {
        _initialEventSkipped = true;
        debugPrint('[Auth] initial event: ${next.runtimeType} user: ${next.asData?.value?.id} route: ${widget.initialRoute}');
        if (next.asData?.value != null && widget.initialRoute == '/pending') {
          debugPrint('[Auth] cached session boot — falling through to signed-in handler');
          // Fall through to normal signed-in handling below.
        } else if (next.asData?.value == null && widget.initialRoute == '/pending') {
          debugPrint('[Auth] cached session gone — going to /login');
          router.navigatorKey.currentState
              ?.pushNamedAndRemoveUntil('/login', (_) => false);
          return;
        } else {
          debugPrint('[Auth] initial event skipped');
          return;
        }
      }

        final previousUser = previous?.asData?.value;
        final currentUser  = next.asData?.value;

        // No real change in user identity — skip
        if (previousUser?.id == currentUser?.id) return;

        // Guard: only one navigation in flight at a time
        if (_isNavigating) return;
        _isNavigating = true; // FIX: was 'isNavigating' (missing underscore)

        final nav = router.navigatorKey.currentState;
        if (nav == null) {
          _isNavigating = false;
          return;
        }

        try {
          if (currentUser == null) {
            // ── Signed out ─────────────────────────────────────────────────
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

            final isPendingRegistration = ref.read(pendingUserIdProvider) != null;
            if (isPendingRegistration) {
              debugPrint('[Auth] Mid-registration — skipping navigation, waiting for completeRegistration()');
              return;
            }

            debugPrint('[Auth] Signed in: ${currentUser.id} → loading profile');

            try {
              ref.invalidate(profileProvider);
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
              debugPrint('[Auth] Profile load error: $e — falling back to /pos');
              nav.pushNamedAndRemoveUntil('/pos', (_) => false);
            }
          }
        } finally {
          _isNavigating = false; // FIX: was 'isNavigating' (missing underscore)
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
      initialRoute: widget.initialRoute, // FIX: was 'initialRoute', must be 'widget.initialRoute'
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