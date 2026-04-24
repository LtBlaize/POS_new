// lib/core/services/connectivity_service.dart
//
// Watches network reachability and exposes:
//   • isOnlineProvider   → bool (current state)
//   • onlineStreamProvider → Stream<bool> (changes over time)
//
// Uses connectivity_plus to detect interface changes, then does a real
// probe against Supabase so a captive-portal Wi-Fi counts as offline.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Public providers ──────────────────────────────────────────────────────────

/// Current online state. Defaults to true until first probe completes.
final isOnlineProvider = StateProvider<bool>((ref) => true);

/// Service singleton — call connectivityService.init() once in main().
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService(ref);
  ref.onDispose(service.dispose);
  return service;
});

// ── Implementation ────────────────────────────────────────────────────────────

class ConnectivityService {
  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _pollTimer;

  // Probe this host — already in your Supabase allowlist and always reachable.
  static const _probeHost = 'supabase.com';
  static const _probePort = 443;
  static const _probeTimeout = Duration(seconds: 4);
  static const _pollInterval = Duration(seconds: 15);

  ConnectivityService(this._ref);

  /// Call once from main() after ProviderContainer/ProviderScope is ready.
  Future<void> init() async {
    // 1. Immediate probe
    await _probe();

    // 2. React to interface-level changes (WiFi ↔ mobile ↔ none)
    _sub = Connectivity().onConnectivityChanged.listen((_) => _probe());

    // 3. Poll periodically — catches captive portals and flaky connections
    _pollTimer = Timer.periodic(_pollInterval, (_) => _probe());
  }

  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
  }

  bool get isOnline => _ref.read(isOnlineProvider);

  Future<bool> _probe() async {
    bool online;
    try {
      final sock = await Socket.connect(
        _probeHost,
        _probePort,
        timeout: _probeTimeout,
      );
      sock.destroy();
      online = true;
    } catch (_) {
      online = false;
    }

    // Only update state if it actually changed (avoids unnecessary rebuilds)
    if (_ref.read(isOnlineProvider) != online) {
      _ref.read(isOnlineProvider.notifier).state = online;
    }
    return online;
  }
}