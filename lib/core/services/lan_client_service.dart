// lib/core/services/lan_client_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

enum LanPingResult { ok, unauthorized, unreachable }

enum PairingIssue { none, unreachable, authFailed }

/// Set to authFailed the moment a request comes back 403 (wrong/stale key).
/// Unlike plain unreachability, a wrong key won't fix itself on retry, so
/// this is surfaced immediately rather than waiting for a failure count.
final pairingIssueProvider = StateProvider<PairingIssue>((ref) => PairingIssue.none);

/// True once this device has successfully fetched orders at least once —
/// i.e. actually reached the POS *and* had its key accepted. Gates the
/// re-pair prompt so it never fires during first-time setup, when
/// unreachable/unauthenticated is the expected, normal state.
final hasEverPairedProvider = StateProvider<bool>((ref) => false);

final cashierIpProvider = StateProvider<String?>((ref) => null);

final lanClientServiceProvider = Provider<LanClientService>((ref) {
  final s = LanClientService(ref);
  ref.onDispose(s.dispose);
  return s;
});

typedef OrdersCallback = void Function(List<Map<String, dynamic>> orders);
typedef WsEventCallback = void Function(Map<String, dynamic> event);

class LanClientService {
  final Ref _ref;
  WebSocketChannel? _ws;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  bool _disposed = false;

  // Callbacks registered by LanOrdersNotifier
  OrdersCallback? _onOrders;
  WsEventCallback? _onEvent;

  LanClientService(this._ref);

  String? get _baseUrl {
    final ip = _ref.read(cashierIpProvider);
    return ip == null ? null : 'http://$ip:8080';
  }

  String? get _wsUrl {
    final ip = _ref.read(cashierIpProvider);
    return ip == null ? null : 'ws://$ip:8080/ws';
  }

  static String? _posKey;

  /// Set at pairing time. Must match the key set on the server.
  static void setPosKey(String key) => _posKey = key;

  /// True once a key has actually been set — used to gate the re-pair
  /// prompt (no point offering to "re-pair" if pairing was never attempted).
  static bool get hasPosKey => _posKey != null && _posKey!.isNotEmpty;

  // ── Public API ─────────────────────────────────────────────────────────────

  void connect({
    required String businessId,
    required OrdersCallback onOrders,
    required WsEventCallback onEvent,
  }) {
    _onOrders = onOrders;
    _onEvent = onEvent;
    _connectWs(businessId);
    // Also do an immediate HTTP fetch to hydrate state before WS is ready
    _fetchOrders(businessId);
  }

  void dispose() {
    _disposed = true;
    _ws?.sink.close();
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();
  }

  /// Send a status update to the POS server. Returns true on success.
  /// Callers should enqueue to LanStatusQueue if this returns false.
  Future<bool> patchStatus(String orderId, String status) async {
    final base = _baseUrl;
    if (base == null) return false;
    try {
      final res = await http
          .patch(
            Uri.parse('$base/orders/$orderId/status'),
            headers: {
              'content-type': 'application/json',
              'x-pos-key': _posKey ?? '',
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 403) {
        _ref.read(pairingIssueProvider.notifier).state = PairingIssue.authFailed;
      } else if (res.statusCode == 200 &&
          _ref.read(pairingIssueProvider) == PairingIssue.authFailed) {
        _ref.read(pairingIssueProvider.notifier).state = PairingIssue.none;
      }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Verifies both that the POS is reachable on LAN *and* that the stored
  /// pairing key is accepted — a plain reachability check isn't enough to
  /// call a device "paired," since /orders/pending and the status PATCH
  /// both reject a wrong/missing key independently of network reachability.
  Future<LanPingResult> ping() async {
    final base = _baseUrl;
    if (base == null) return LanPingResult.unreachable;
    try {
      final res = await http
          .get(
            Uri.parse('$base/ping'),
            headers: {'x-pos-key': _posKey ?? ''},
          )
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return LanPingResult.ok;
      if (res.statusCode == 403) return LanPingResult.unauthorized;
      return LanPingResult.unreachable;
    } catch (_) {
      return LanPingResult.unreachable;
    }
  }

  // ── WebSocket ──────────────────────────────────────────────────────────────

  void _connectWs(String businessId) {
    if (_disposed || _wsUrl == null) return;
    _ws?.sink.close();

    try {
      _ws = WebSocketChannel.connect(Uri.parse(_wsUrl!));
      _ws!.stream.listen(
        (raw) => _handleWsMessage(raw as String, businessId),
        onDone: () => _scheduleReconnect(businessId),
        onError: (_) => _scheduleReconnect(businessId),
        cancelOnError: true,
      );
      // WS connected — cancel any poll fallback
      _pollTimer?.cancel();
      _pollTimer = null;
      debugPrint('[LAN] WebSocket connected to $_wsUrl');
    } catch (_) {
      _scheduleReconnect(businessId);
    }
  }

  void _handleWsMessage(String raw, String businessId) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      _onEvent?.call(msg);

      // On any order change, re-fetch the full list so UI is in sync
      if (msg['type'] == 'order_placed' || msg['type'] == 'order_status_changed') {
        _fetchOrders(businessId);
      }
      // Parked order events are handled by ParkedOrderNotifier via onEvent
    } catch (e) {
      debugPrint('[LAN] WS parse error: $e');
    }
  }

  void _scheduleReconnect(String businessId) {
    if (_disposed) return;
    debugPrint('[LAN] WS disconnected — falling back to polling');
    // Start poll fallback so kitchen isn't blind while WS is down
    _startPolling(businessId);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connectWs(businessId);
    });
  }

  // ── Poll fallback ──────────────────────────────────────────────────────────

  void _startPolling(String businessId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchOrders(businessId);
    });
    _fetchOrders(businessId); // immediate
  }

  Future<void> _fetchOrders(String businessId) async {
    final base = _baseUrl;
    if (base == null) return;
    try {
      final res = await http
          .get(
            Uri.parse('$base/orders/pending?business_id=$businessId'),
            headers: {'x-pos-key': _posKey ?? ''},
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        _onOrders?.call(list);

        // A 200 here proves both reachability and a correct key — clear any
        // auth-failure flag and record that pairing has genuinely succeeded
        // at least once (whether this is the very first connect or a
        // reconnect after an outage doesn't matter — either way it's proof
        // this device isn't in first-time setup anymore).
        if (_ref.read(pairingIssueProvider) != PairingIssue.none) {
          _ref.read(pairingIssueProvider.notifier).state = PairingIssue.none;
        }
        if (!_ref.read(hasEverPairedProvider)) {
          _ref.read(hasEverPairedProvider.notifier).state = true;
        }
      } else if (res.statusCode == 403) {
        // Wrong/stale key — reachability isn't the problem, so flag this
        // immediately rather than waiting on the sustained-failure timer
        // connectivity_service uses for plain unreachability.
        _ref.read(pairingIssueProvider.notifier).state = PairingIssue.authFailed;
      }
    } catch (_) {
      // POS unreachable on LAN — connectivity_service's needsRepairProvider
      // already tracks this via its own TCP probe on a separate timer.
    }
  }
}