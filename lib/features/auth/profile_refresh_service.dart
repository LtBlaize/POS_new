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
import '../../core/services/connectivity_service.dart';
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
    // Runs even while kEnforceCoreAccess is false: a plan change (e.g. a
    // downgrade) has to reach open devices. _tick keeps the full refresh
    // gated and does a cheap plan check otherwise.

    _authSub = _ref.listen<AsyncValue<dynamic>>(authStateProvider, (
      prev,
      next,
    ) {
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
    _timer = Timer.periodic(_kProfileRefreshInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_ref.read(authStateProvider).valueOrNull == null) return;
    if (!_ref.read(isOnlineProvider)) return;

    // Enforcement live: same full refresh as before.
    if (kEnforceCoreAccess) {
      _ref.invalidate(profileProvider);
      return;
    }

    // Enforcement off: one tiny query, and only reload the profile if the
    // plan or active flag actually changed. A blind invalidate would blank
    // profileProvider for a moment and reset the POS tab on every device.
    final biz = _ref.read(businessProvider);
    if (biz == null) return;
    try {
      final row = await _ref
          .read(supabaseClientProvider)
          .from('businesses')
          .select('subscription_plan, is_active')
          .eq('id', biz.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      if (row == null) return;
      if (row['subscription_plan'] != biz.subscriptionPlan.value ||
          row['is_active'] != biz.isActive) {
        _ref.invalidate(profileProvider);
      }
    } catch (_) {
      // Offline or slow: try again next tick.
    }
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
