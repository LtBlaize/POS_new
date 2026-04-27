// lib/core/services/connectivity_service.dart
//
// Watches both internet reachability AND local LAN reachability, exposing:
//   • isOnlineProvider       → bool  (internet)
//   • isLanConnectedProvider → bool  (POS reachable on LAN)
//
// Uses connectivity_plus to detect interface changes, then does a real TCP
// probe so a captive-portal Wi-Fi counts as offline.
//
// LAN probe pings the POS HTTP server directly on port 8080. This is
// independent of internet — the kitchen can be LAN-live while internet is dead.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lan_client_service.dart';

// ── Public providers ───────────────────────────────────────────────────────────

/// True when internet is reachable. Defaults to true until first probe.
final isOnlineProvider = StateProvider<bool>((ref) => true);

/// True when the POS device is reachable on the local network.
/// Only meaningful on the kitchen device.
final isLanConnectedProvider = StateProvider<bool>((ref) => false);

/// Combined connectivity state — used by the offline banner.
final connectivityStatusProvider = Provider<ConnectivityStatus>((ref) {
  final internet = ref.watch(isOnlineProvider);
  final lan = ref.watch(isLanConnectedProvider);
  if (internet && lan) return ConnectivityStatus.full;
  if (!internet && lan) return ConnectivityStatus.lanOnly;
  if (internet && !lan) return ConnectivityStatus.internetOnly;
  return ConnectivityStatus.none;
});

enum ConnectivityStatus {
  full,          // ● Green:  Internet ✓  LAN ✓
  lanOnly,       // ● Amber:  Internet ✗  LAN ✓  (local only, syncs later)
  internetOnly,  // ● Blue:   Internet ✓  LAN ✗  (POS server not started?)
  none,          // ● Red:    Internet ✗  LAN ✗
}

/// Service singleton — call connectivityService.init() once in main().
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService(ref);
  ref.onDispose(service.dispose);
  return service;
});

// ── Implementation ─────────────────────────────────────────────────────────────

class ConnectivityService {
  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _internetPollTimer;
  Timer? _lanPollTimer;

  // Internet probe target — reliable, always up
  static const _internetHost = 'supabase.com';
  static const _internetPort = 443;
  static const _probeTimeout = Duration(seconds: 4);
  static const _internetPollInterval = Duration(seconds: 15);

  // LAN probe — checks if POS server is up on port 8080
  static const _lanPort = 8080;
  static const _lanTimeout = Duration(seconds: 2);
  static const _lanPollInterval = Duration(seconds: 5);

  ConnectivityService(this._ref);

  /// Call once from main() after ProviderScope is ready.
  Future<void> init() async {
    // Immediate probes
    await _probeInternet();
    await _probeLan();

    // React to interface-level changes (WiFi ↔ mobile ↔ none)
    _sub = Connectivity().onConnectivityChanged.listen((_) async {
      await _probeInternet();
      await _probeLan();
    });

    // Periodic polls — catches captive portals and flaky connections
    _internetPollTimer =
        Timer.periodic(_internetPollInterval, (_) => _probeInternet());
    _lanPollTimer =
        Timer.periodic(_lanPollInterval, (_) => _probeLan());
  }

  void dispose() {
    _sub?.cancel();
    _internetPollTimer?.cancel();
    _lanPollTimer?.cancel();
  }

  bool get isOnline => _ref.read(isOnlineProvider);
  bool get isLanConnected => _ref.read(isLanConnectedProvider);

  // ── Internet probe ─────────────────────────────────────────────────────────

  Future<bool> _probeInternet() async {
    bool online;
    try {
      final sock = await Socket.connect(
        _internetHost,
        _internetPort,
        timeout: _probeTimeout,
      );
      sock.destroy();
      online = true;
    } catch (_) {
      online = false;
    }

    if (_ref.read(isOnlineProvider) != online) {
      _ref.read(isOnlineProvider.notifier).state = online;
      debugPrint('[Connectivity] Internet: ${online ? "online" : "offline"}');
    }
    return online;
  }

  // ── LAN probe ──────────────────────────────────────────────────────────────

  /// Probe the POS server directly. Pass [posIp] to override the stored IP,
  /// or leave null to use cashierIpProvider.
  Future<bool> probeLan([String? posIp]) async {
    final ip = posIp ?? _ref.read(cashierIpProvider);
    if (ip == null || ip.isEmpty) {
      // No IP configured yet — can't probe
      _setLan(false);
      return false;
    }

    bool reachable;
    try {
      final sock = await Socket.connect(
        ip,
        _lanPort,
        timeout: _lanTimeout,
      );
      sock.destroy();
      reachable = true;
    } catch (_) {
      reachable = false;
    }

    _setLan(reachable);
    return reachable;
  }

  Future<bool> _probeLan() => probeLan();

  void _setLan(bool reachable) {
    if (_ref.read(isLanConnectedProvider) != reachable) {
      _ref.read(isLanConnectedProvider.notifier).state = reachable;
      debugPrint(
          '[Connectivity] LAN: ${reachable ? "reachable" : "unreachable"}');
    }
  }

  // ── Manual force-check ─────────────────────────────────────────────────────

  /// Force an immediate check of both. Useful on app resume.
  Future<void> recheck() async {
    await Future.wait([_probeInternet(), _probeLan()]);
  }
}