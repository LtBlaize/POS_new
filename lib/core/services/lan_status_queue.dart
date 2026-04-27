// lib/core/services/lan_status_queue.dart
//
// Lightweight in-memory queue for kitchen status updates.
// When the POS is temporarily unreachable on LAN, updates are held here
// and replayed every 3 seconds until they succeed.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lan_client_service.dart';

final lanStatusQueueProvider = Provider<LanStatusQueue>((ref) {
  final q = LanStatusQueue(ref.read(lanClientServiceProvider));
  ref.onDispose(q.dispose);
  return q;
});

class _PendingPatch {
  final String orderId;
  String status;
  int attempts;
  _PendingPatch(this.orderId, this.status) : attempts = 0;
}

class LanStatusQueue {
  final LanClientService _client;
  final List<_PendingPatch> _queue = [];
  Timer? _timer;
  static const _maxAttempts = 20; // ~60s total before giving up

  LanStatusQueue(this._client);

  /// Enqueue a status update. Immediately attempts to send; retries if it fails.
  void enqueue(String orderId, String status) {
    // Deduplicate: if already queued for same order, update status in place
    final existing = _queue.where((p) => p.orderId == orderId).firstOrNull;
    if (existing != null) {
      existing.status = status; // promote to latest status
      existing.attempts = 0;
    } else {
      _queue.add(_PendingPatch(orderId, status));
    }
    _flush();
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => _flush());
  }

  void dispose() {
    _timer?.cancel();
  }

  Future<void> _flush() async {
    if (_queue.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    final toRemove = <_PendingPatch>[];
    for (final patch in List.of(_queue)) {
      if (patch.attempts >= _maxAttempts) {
        debugPrint('[LanQueue] Giving up on ${patch.orderId} after ${patch.attempts} attempts');
        toRemove.add(patch);
        continue;
      }
      patch.attempts++;
      final ok = await _client.patchStatus(patch.orderId, patch.status);
      if (ok) {
        debugPrint('[LanQueue] Sent ${patch.orderId} → ${patch.status}');
        toRemove.add(patch);
      }
    }
    _queue.removeWhere(toRemove.contains);
  }
}

// Riverpod extension for easy access
extension LanStatusQueueX on LanStatusQueue {
  String get pendingCount => '${_queue.length}';
}