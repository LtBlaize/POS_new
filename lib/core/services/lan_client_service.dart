import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

// Persisted by kitchen device — set once when cashier shows QR/IP
final cashierIpProvider = StateProvider<String?>((ref) => null);

final lanClientServiceProvider = Provider<LanClientService>((ref) {
  return LanClientService(ref);
});

class LanClientService {
  final Ref _ref;
  Timer? _pollTimer;

  LanClientService(this._ref);

  String? get _baseUrl {
    final ip = _ref.read(cashierIpProvider);
    if (ip == null) return null;
    return 'http://$ip:8080';
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  /// Starts polling every [intervalSeconds] seconds.
  /// [onOrders] is called with fresh order data each tick.
  void startPolling({
    required String businessId,
    required void Function(List<Map<String, dynamic>>) onOrders,
    required void Function(String) onError,
    int intervalSeconds = 5,
  }) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _fetchOrders(businessId, onOrders, onError),
    );
    // Immediate first fetch
    _fetchOrders(businessId, onOrders, onError);
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchOrders(
    String businessId,
    void Function(List<Map<String, dynamic>>) onOrders,
    void Function(String) onError,
  ) async {
    final base = _baseUrl;
    if (base == null) return;

    try {
      final res = await http
          .get(Uri.parse('$base/orders/pending?business_id=$businessId'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        onOrders(list.cast<Map<String, dynamic>>());
      } else {
        onError('Server error: ${res.statusCode}');
      }
    } catch (e) {
      onError('Cannot reach cashier: $e');
    }
  }

  // ── Mark order ready ───────────────────────────────────────────────────────

  Future<bool> markReady(String orderId) async {
    final base = _baseUrl;
    if (base == null) return false;

    try {
      final res = await http
          .patch(
            Uri.parse('$base/orders/$orderId/status'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'status': 'completed'}),
          )
          .timeout(const Duration(seconds: 3));

      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Connection check ───────────────────────────────────────────────────────

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
}