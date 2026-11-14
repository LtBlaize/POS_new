// lib/main.dart
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'features/auth/profile_refresh_service.dart';
import 'features/auth/register_screen.dart'; // for pendingUserIdProvider

// ── Device role ────────────────────────────────────────────────────────────────
final deviceRoleProvider = StateProvider<DeviceRole>((ref) => DeviceRole.pos);

enum DeviceRole { pos, kitchen }

enum RepairPromptReason { unreachable, authFailed }

/// Single gate for the re-pair dialog. Every condition here is deliberately
/// conservative — any one being false suppresses the prompt entirely:
///   - kitchen device only (POS never has cashierIpProvider set, so this
///     would naturally be null there anyway, but the role check makes the
///     intent explicit rather than relying on that as a side effect)
///   - pairing info must actually exist (no IP/key = nothing to re-pair)
///   - must have paired successfully before (never prompt during first-time
///     setup, when "can't reach POS yet" is the expected starting state)
///   - "no network at all" is not a pairing problem — the banner already
///     covers it, and a dialog on top of a plain WiFi drop is just noise
final repairPromptReasonProvider = Provider<RepairPromptReason?>((ref) {
  if (ref.watch(deviceRoleProvider) != DeviceRole.kitchen) return null;

  final hasIp = ref.watch(cashierIpProvider) != null;
  if (!hasIp || !LanClientService.hasPosKey) return null;

  if (!ref.watch(hasEverPairedProvider)) return null;

  if (ref.watch(connectivityStatusProvider) == ConnectivityStatus.none) {
    return null;
  }

  // Auth failure is checked first and reported immediately — no threshold,
  // since a wrong key doesn't get better with more retries.
  if (ref.watch(pairingIssueProvider) == PairingIssue.authFailed) {
    return RepairPromptReason.authFailed;
  }

  // needsRepairProvider is connectivity_service's sustained-failure signal —
  // ~30s / 6 consecutive TCP probe failures against the paired IP.
  if (ref.watch(needsRepairProvider)) {
    return RepairPromptReason.unreachable;
  }

  return null;
});

// ── Entry point ────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
      overlays: SystemUiOverlay.values);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
    debugPrint(
      '[Boot] Cached session found for ${existingSession.user.id} — '
      'letting SDK auto-refresh handle validity (autoRefreshToken: true)',
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer();

  await container.read(localDbServiceProvider).db;

  final savedRole = prefs.getString('device_role');
  DeviceRole role = DeviceRole.pos;
  if (savedRole != null) {
    role = DeviceRole.values.byNameOrNull(savedRole) ?? DeviceRole.pos;
    container.read(deviceRoleProvider.notifier).state = role;
  }

  final isPos = savedRole == null || role == DeviceRole.pos;
  final isKitchen = role == DeviceRole.kitchen;

  if (isPos) {
    final businessId = prefs.getString('business_id') ?? '';
    if (businessId.isNotEmpty) {
      try {
        await container
            .read(localDbServiceProvider)
            .clearStaleData(businessId)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[Boot] clearStaleData failed (non-fatal): $e');
      }
    }
  }

  try {
    await container
        .read(connectivityServiceProvider)
        .init()
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Boot] connectivity init failed (non-fatal): $e');
  }
  container.read(
    syncQueueServiceProvider,
  ); // provider factory already calls init()
  container.read(profileRefreshServiceProvider).init();

  if (isPos) {
    final savedKey = prefs.getString('pos_lan_key');
    if (savedKey != null && savedKey.isNotEmpty) {
      LanServerService.setPosKey(savedKey);
    } else {
      final newKey = LanServerService.getPosKey(); // generates one
      await prefs.setString('pos_lan_key', newKey);
    }
    try {
      await container
          .read(lanServerServiceProvider)
          .start()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[Boot] LAN server failed to start (non-fatal): $e');
    }
    try {
      if (!kIsWeb && Platform.isAndroid) await WakelockPlus.enable();
    } catch (e) {
      debugPrint('[Boot] Wakelock failed (non-fatal): $e');
    }
    try {
      final ip = await _getLocalIp().timeout(const Duration(seconds: 3));
      if (ip != null) {
        await prefs.setString('pos_local_ip', ip);
        debugPrint('[Boot] POS local IP: $ip');
      }
    } catch (e) {
      debugPrint('[Boot] local IP lookup failed (non-fatal): $e');
    }
  }

  if (isKitchen) {
    final savedKey = prefs.getString('pos_lan_key');
    if (savedKey != null && savedKey.isNotEmpty) {
      LanClientService.setPosKey(savedKey);
    }
    container.read(hasEverPairedProvider.notifier).state =
        prefs.getBool('has_paired_pos') ?? false;
    final cachedIp = prefs.getString('cashier_ip');
    if (cachedIp != null && cachedIp.isNotEmpty) {
      container.read(cashierIpProvider.notifier).state = cachedIp;
      bool reachable = false;
      try {
        reachable = await container
            .read(connectivityServiceProvider)
            .probeLan(cachedIp)
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('[Boot] probeLan failed (non-fatal): $e');
      }
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
      Supabase.instance.client.auth.currentSession != null
          ? '/pending'
          : '/login';

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

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  String? _handledUserId;
  bool _isNavigating = false;
  bool _repairDialogShowing = false;

  @override
  void initState() {
    super.initState();
    // The user the boot route already accounts for.
    _handledUserId = Supabase.instance.client.auth.currentUser?.id;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Force a fresh frame so a stale surface doesn't stay black.
      WidgetsBinding.instance.scheduleForcedFrame();
      WidgetsBinding.instance.handleBeginFrame(null);
      WidgetsBinding.instance.handleDrawFrame();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
      if (next.isLoading || next.hasError) return;
      final user = next.valueOrNull;

      // Already handled (boot route covers it, or a duplicate event).
      if (user?.id == _handledUserId) return;

      if (_isNavigating) return;
      final nav = router.navigatorKey.currentState;
      if (nav == null) return;

      if (user == null) {
        _handledUserId = null;
        debugPrint('[Auth] Signed out → /login');
        nav.pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }

      if (RecoveryGuard.isRecovering) {
        debugPrint('[Auth] Mid-password-reset — skipping navigation');
        return;
      }
      if (ref.read(pendingUserIdProvider) != null) {
        debugPrint('[Auth] Mid-registration — skipping navigation');
        return;
      }

      _isNavigating = true;
      _handledUserId = user.id;
      debugPrint('[Auth] Signed in: ${user.id} → /pending');
      nav.pushNamedAndRemoveUntil('/pending', (_) => false);
      _isNavigating = false;
    });

    // ── Persist "has this device ever paired successfully" ─────────────────
    ref.listen<bool>(hasEverPairedProvider, (prev, next) async {
      if (next && prev != true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_paired_pos', true);
      }
    });

    // ── Re-pair prompt ───────────────────────────────────────────────────────
    // Edge-triggered: only fires on an actual change in reason, so it won't
    // re-show every rebuild while an outage is ongoing, and won't spam the
    // user after they dismiss it with "Keep Trying" unless the underlying
    // issue changes (e.g. unreachable → authFailed) or clears and recurs.
    ref.listen<RepairPromptReason?>(repairPromptReasonProvider, (
      previous,
      next,
    ) {
      if (next == null || previous == next || _repairDialogShowing) return;
      final ctx = router.navigatorKey.currentContext;
      if (ctx == null) return;
      _showRepairPrompt(ctx, next);
    });

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
            borderRadius: BorderRadius.circular(10),
          ),
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
      initialRoute:
          widget
              .initialRoute, // FIX: was 'initialRoute', must be 'widget.initialRoute'
      onGenerateRoute: router.onGenerateRoute,
    );
  }

  void _showRepairPrompt(BuildContext context, RepairPromptReason reason) {
    final (title, message) = switch (reason) {
      RepairPromptReason.authFailed => (
        'Pairing key rejected',
        "This device reached the POS, but the saved pairing key doesn't "
            "match. Orders can't be sent or received until this is fixed.",
      ),
      RepairPromptReason.unreachable => (
        "Can't reach POS",
        "This device hasn't been able to reach the POS for a while. "
            "It'll keep retrying in the background — but if the POS's "
            "network address changed, re-pairing will fix it faster.",
      ),
    };

    _repairDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: true, // tapping outside = same as Keep Trying
      builder:
          (dialogCtx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Keep Trying'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  Navigator.of(context).pushNamed('/ip-setup');
                },
                child: const Text('Re-pair POS'),
              ),
            ],
          ),
    ).then((_) => _repairDialogShowing = false);
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
