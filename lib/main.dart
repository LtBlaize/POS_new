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

// ── Device role ────────────────────────────────────────────────────────────────
final deviceRoleProvider = StateProvider<DeviceRole>((ref) => DeviceRole.pos);

enum DeviceRole { pos, kitchen }

// ── Entry point ────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop FFI init — not needed on Android/iOS (uses native sqflite)
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await Supabase.initialize(
    url: 'https://qsdbufdixhyqlbygrncp.supabase.co',
    anonKey: 'sb_publishable_IMKcLGls9al71UvjElf_Kw_iC0N4Dqu',
  );

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer();

  // 1. Local DB — wait for it to be ready
  await container.read(localDbServiceProvider).db;

  // 2. Load saved device role
  //    null  = first launch (or retail auto-assigned later in login)
  //    'pos' / 'kitchen' = previously chosen
  final savedRole = prefs.getString('device_role');

  DeviceRole role = DeviceRole.pos; // safe default for boot services
  if (savedRole != null) {
    role = DeviceRole.values.byNameOrNull(savedRole) ?? DeviceRole.pos;
    container.read(deviceRoleProvider.notifier).state = role;
  }

  final isPos     = savedRole == null || role == DeviceRole.pos;
  final isKitchen = role == DeviceRole.kitchen;

  // 3. Prune old synced orders on POS boot
  if (isPos) {
    final businessId = prefs.getString('business_id') ?? '';
    if (businessId.isNotEmpty) {
      await container
          .read(localDbServiceProvider)
          .clearStaleData(businessId);
    }
  }

  // 4. Connectivity (internet probe + LAN probe)
  await container.read(connectivityServiceProvider).init();

  // 5. Sync queue — flushes to Supabase on internet reconnect
  container.read(syncQueueServiceProvider).init();

  // 6. POS: start the LAN HTTP + WebSocket server
  if (isPos) {
    await container.read(lanServerServiceProvider).start();

    if (!kIsWeb && Platform.isAndroid) {
      await WakelockPlus.enable();
    }

    final ip = await _getLocalIp();
    if (ip != null) {
      await prefs.setString('pos_local_ip', ip);
      debugPrint('[Boot] POS server started — local IP: $ip');
    }
  }

  // 7. Kitchen: restore saved POS IP and connect
  if (isKitchen) {
    final cachedIp = prefs.getString('cashier_ip');
    if (cachedIp != null && cachedIp.isNotEmpty) {
      container.read(cashierIpProvider.notifier).state = cachedIp;
      debugPrint('[Boot] Kitchen — POS IP restored: $cachedIp');

      final reachable = await container
          .read(connectivityServiceProvider)
          .probeLan(cachedIp);

      if (reachable) {
        final businessId = prefs.getString('business_id') ?? '';
        container.read(kitchenStateProvider.notifier).connect(businessId);
        debugPrint('[Boot] Kitchen — LAN client connected to $cachedIp');
      }
    } else {
      debugPrint(
          '[Boot] Kitchen — no POS IP saved. Open Settings → Connect to POS.');
    }
  }

  // 8. Determine initial route
  //
  //   Priority order:
  //   a) Has active Supabase session → already logged in → /pos
  //   b) No session → go to /login
  //
  //   Role selection (/role-select) is NEVER an initial route.
  //   It is shown AFTER login only for restaurant accounts that haven't
  //   chosen a device role yet. Retail accounts never see it.
  //   See login_screen.dart → _submit() for that logic.
  final String initialRoute;
  if (Supabase.instance.client.auth.currentSession != null) {
    initialRoute = '/pos';
  } else {
    initialRoute = '/login';
  }

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

    // Show a toast whenever SyncQueueService finishes a flush
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

/// Returns the device's current WiFi/LAN IPv4 address.
Future<String?> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
  } catch (e) {
    debugPrint('[Boot] Could not determine local IP: $e');
  }
  return null;
}

// ── Extension ─────────────────────────────────────────────────────────────────

extension _EnumByNameOrNull<T extends Enum> on Iterable<T> {
  T? byNameOrNull(String name) {
    for (final v in this) {
      if (v.name == name) return v;
    }
    return null;
  }
}

// ── Helpers exposed to other files ────────────────────────────────────────────

/// Persist the POS IP on the kitchen device.
/// Called after QR scan or manual entry in ip_setup_screen.dart.
Future<void> savePosIp(String ip, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('cashier_ip', ip);
  ref.read(cashierIpProvider.notifier).state = ip;
  debugPrint('[Settings] POS IP saved: $ip');
}

/// Read the local IP cached at boot — used by the QR display on the POS.
Future<String?> readPosLocalIp() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('pos_local_ip');
}