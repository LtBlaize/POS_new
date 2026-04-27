// lib/core/services/lan_client_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

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
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ping() async {
    final base = _baseUrl;
    if (base == null) return false;
    try {
      final res = await http
          .get(Uri.parse('$base/ping'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
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
          .get(Uri.parse('$base/orders/pending?business_id=$businessId'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        _onOrders?.call(list);
      }
    } catch (_) {
      // POS is unreachable on LAN — notifier will show stale state
    }
  }
}