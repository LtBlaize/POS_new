// lib/main.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_router.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/lan_client_service.dart';
import 'core/services/lan_server_service.dart';
import 'core/services/local_db_service.dart';
import 'core/services/sync_queue_service.dart';

// ── Device role ────────────────────────────────────────────────────────────────
//
// POS     = Windows / Linux / macOS desktop  → runs LAN HTTP + WebSocket server
// Kitchen = Android / iOS tablet             → connects to POS over LAN
//
// Role is inferred from the platform — no manual configuration needed.

bool get _isPosDevice =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get _isKitchenDevice =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

final deviceRoleProvider = Provider<DeviceRole>((ref) {
  if (_isPosDevice) return DeviceRole.pos;
  if (_isKitchenDevice) return DeviceRole.kitchen;
  return DeviceRole.pos; // web fallback
});

enum DeviceRole { pos, kitchen }

// ── Entry point ────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop only — Android/iOS use native sqflite, no FFI needed
  if (_isPosDevice) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await Supabase.initialize(
    url: 'https://qsdbufdixhyqlbygrncp.supabase.co',
    anonKey: 'sb_publishable_IMKcLGls9al71UvjElf_Kw_iC0N4Dqu',
  );

  final container = ProviderContainer();

  // 1. Local DB — wait for it to be ready
  await container.read(localDbServiceProvider).db;

  // 2. Connectivity (internet probe + LAN probe)
  await container.read(connectivityServiceProvider).init();

  // 3. Sync queue — starts listening for internet reconnects → flush to Supabase
  container.read(syncQueueServiceProvider).init();

  // 4a. POS (desktop): start the LAN HTTP + WebSocket server
  if (_isPosDevice) {
    await container.read(lanServerServiceProvider).start();

    // Cache the local IP so the QR screen can read it without async work
    final ip = await _getLocalIp();
    if (ip != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pos_local_ip', ip);
      debugPrint('[Boot] POS server started — local IP: $ip');
    }
  }

  // 4b. Kitchen (mobile/tablet): restore the saved POS IP
  if (_isKitchenDevice) {
    final prefs = await SharedPreferences.getInstance();
    final cachedIp = prefs.getString('cashier_ip');
    if (cachedIp != null && cachedIp.isNotEmpty) {
      container.read(cashierIpProvider.notifier).state = cachedIp;
      debugPrint('[Boot] Kitchen — POS IP restored: $cachedIp');
      // Probe in background — sets isLanConnectedProvider before first frame
      _unawaited(
        container.read(connectivityServiceProvider).probeLan(cachedIp),
      );
    } else {
      debugPrint('[Boot] Kitchen — no POS IP saved. Open Settings → Connect to POS.');
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

// ── Root app ───────────────────────────────────────────────────────────────────

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      initialRoute: '/login',
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Returns the device's current WiFi/LAN IPv4 address.
/// Uses dart:io NetworkInterface directly — no extra package required.
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

/// Explicitly discards a Future — avoids unawaited_futures lint
/// without pulling in async_helper package.
void _unawaited(Future<void> future) {
  future.catchError((Object e) => debugPrint('[unawaited] $e'));
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