// lib/core/services/lan_status_queue.dart
//
// Persistent queue for kitchen status updates sent to the POS over LAN.
//
// Kitchen devices never write directly to Supabase — the LAN channel to the
// POS is the only path for status updates. So a pending update must never
// be lost: not because the app restarted mid-outage, not because a patch
// kept failing. Every entry here is retried indefinitely, with a capped
// exponential backoff, and is removed only once the POS actually
// acknowledges it with a 200.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connectivity_service.dart';
import 'lan_client_service.dart';

final lanStatusQueueProvider = Provider<LanStatusQueue>((ref) {
  final q = LanStatusQueue(ref, ref.read(lanClientServiceProvider));
  ref.onDispose(q.dispose);
  return q;
});

/// Live pending count — for a badge in Settings/kitchen UI.
final lanQueuePendingCountProvider = StateProvider<int>((ref) => 0);

const _prefsKey = 'lan_status_queue_v1';

class _PendingPatch {
  final String orderId;
  String status;
  int attempts;
  final int queuedAtMs;
  DateTime nextAttemptAt;

  _PendingPatch({
    required this.orderId,
    required this.status,
    this.attempts = 0,
    int? queuedAtMs,
    DateTime? nextAttemptAt,
  })  : queuedAtMs = queuedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        nextAttemptAt = nextAttemptAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'status': status,
        'attempts': attempts,
        'queuedAtMs': queuedAtMs,
      };

  // Due immediately on load — after a restart, a patch shouldn't have to
  // wait out a backoff window it was already partway through.
  factory _PendingPatch.fromJson(Map<String, dynamic> json) => _PendingPatch(
        orderId: json['orderId'] as String,
        status: json['status'] as String,
        attempts: json['attempts'] as int? ?? 0,
        queuedAtMs: json['queuedAtMs'] as int?,
        nextAttemptAt: DateTime.now(),
      );
}

class LanStatusQueue {
  final Ref _ref;
  final LanClientService _client;
  final List<_PendingPatch> _queue = [];

  Timer? _timer;
  bool _flushing = false;
  late final Future<void> _ready;
  ProviderSubscription<bool>? _lanSub;

  static const _tickInterval = Duration(seconds: 3);
  static const _baseDelay = Duration(seconds: 2);
  static const _maxDelay = Duration(seconds: 60);

  LanStatusQueue(this._ref, this._client) {
    _ready = _load();
    // Flush immediately when LAN comes back, rather than waiting for the
    // next 3s tick — matters most right after a re-pair or outage ends.
    _lanSub = _ref.listen<bool>(isLanConnectedProvider, (prev, next) {
      if (next == true && prev != true) _flush();
    });
  }

  int get pendingCount => _queue.length;

  /// Enqueue a status update. Immediately attempts to send; retries
  /// indefinitely until the POS acknowledges it — never dropped.
  void enqueue(String orderId, String status) {
    _withReady(() async {
      final existing = _queue.where((p) => p.orderId == orderId).firstOrNull;
      if (existing != null) {
        // A newer status supersedes the old one and gets a fresh attempt
        // immediately, instead of waiting out the prior entry's backoff.
        existing.status = status;
        existing.attempts = 0;
        existing.nextAttemptAt = DateTime.now();
      } else {
        _queue.add(_PendingPatch(orderId: orderId, status: status));
      }
      await _persist();
      _updateCount();
      _ensureTimer();
      unawaited(_flush());
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lanSub?.close();
    // Deliberately NOT clearing _queue or storage here — pending patches
    // must survive provider disposal exactly as they survive an app kill.
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _queue
        ..clear()
        ..addAll(list.map(_PendingPatch.fromJson));
      _updateCount();
      if (_queue.isNotEmpty) {
        debugPrint('[LanQueue] Restored ${_queue.length} pending patch(es) from disk');
        _ensureTimer();
      }
    } catch (e) {
      debugPrint('[LanQueue] Failed to load persisted queue: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_queue.map((p) => p.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      // Persistence failing is itself worth knowing about, but must not
      // block the in-memory retry loop — that's still our safety net.
      debugPrint('[LanQueue] Failed to persist queue: $e');
    }
  }

  Future<void> _withReady(FutureOr<void> Function() fn) async {
    await _ready;
    await fn();
  }

  // ── Flush ───────────────────────────────────────────────────────────────

  void _ensureTimer() {
    _timer ??= Timer.periodic(_tickInterval, (_) => _flush());
  }

  Future<void> _flush() async {
    await _ready;
    if (_flushing) return;
    _flushing = true;
    try {
      if (_queue.isEmpty) {
        _timer?.cancel();
        _timer = null;
        return;
      }

      final now = DateTime.now();
      var changed = false;

      for (final patch in List.of(_queue)) {
        if (patch.nextAttemptAt.isAfter(now)) continue; // backoff not elapsed yet

        patch.attempts++;
        final ok = await _client.patchStatus(patch.orderId, patch.status);

        if (ok) {
          debugPrint('[LanQueue] POS acknowledged ${patch.orderId} → ${patch.status}');
          _queue.remove(patch);
        } else {
          // Reschedule further out — never removed, never given up on.
          // Exponent capped so the backoff calc stays cheap; the delay
          // itself is separately capped at _maxDelay below.
          final exp = math.min(patch.attempts - 1, 10);
          final delayMs = (_baseDelay.inMilliseconds * (1 << exp))
              .clamp(_baseDelay.inMilliseconds, _maxDelay.inMilliseconds);
          patch.nextAttemptAt = now.add(Duration(milliseconds: delayMs));
          debugPrint(
              '[LanQueue] ${patch.orderId} attempt ${patch.attempts} failed — retrying in ${delayMs ~/ 1000}s');
        }
        changed = true;
      }

      if (changed) {
        await _persist();
        _updateCount();
      }
    } finally {
      _flushing = false;
    }
  }

  void _updateCount() {
    _ref.read(lanQueuePendingCountProvider.notifier).state = _queue.length;
  }
}