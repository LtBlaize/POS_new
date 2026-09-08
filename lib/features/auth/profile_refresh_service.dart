// lib/features/auth/profile_refresh_service.dart
//
// Closes the staleness gap in profileProvider: without this, a
// long-running session never re-fetches Business/subscription state after
// initial login, so an admin-side suspension or expiry wouldn't be
// reflected on an already-open device until app restart or re-login.
//
// Session-scoped periodic refresh — starts when a session exists, stops
// (and cancels its timer) the moment it doesn't, so there's never more
// than one timer alive and nothing survives past logout.
//
// Gated behind kEnforceCoreAccess: while that flag is false, invalidating
// profileProvider every 5 minutes is just wasted network calls, since
// hasCoreAccess ignores the result anyway (see feature_manager.dart).
// Flip both together once backfill + verification are done.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/access_enforcement_flag.dart';
import 'auth_provider.dart';

const _kProfileRefreshInterval = Duration(minutes: 5);

final profileRefreshServiceProvider = Provider<ProfileRefreshService>((ref) {
  final service = ProfileRefreshService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class ProfileRefreshService {
  final Ref _ref;
  ProviderSubscription<AsyncValue<dynamic>>? _authSub;
  Timer? _timer;

  ProfileRefreshService(this._ref);

  /// Call once from main() after ProviderScope is ready — mirrors the
  /// init() pattern used by ConnectivityService/SyncQueueService.
  void init() {
    if (!kEnforceCoreAccess) return; // no-op until enforcement is live

    _authSub = _ref.listen<AsyncValue<dynamic>>(authStateProvider, (prev, next) {
      final hasSession = next.valueOrNull != null;
      if (hasSession) {
        _startTimer();
      } else {
        _stopTimer();
      }
    });

    // Cover the case where a session already exists at boot (cached
    // session restore) — the listener above only fires on a *change*.
    if (_ref.read(authStateProvider).valueOrNull != null) {
      _startTimer();
    }
  }

  void _startTimer() {
    if (_timer != null) return; // already running — don't stack timers
    _timer = Timer.periodic(_kProfileRefreshInterval, (_) {
      if (_ref.read(authStateProvider).valueOrNull != null) {
        _ref.invalidate(profileProvider);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _authSub?.close();
    _stopTimer();
  }
}