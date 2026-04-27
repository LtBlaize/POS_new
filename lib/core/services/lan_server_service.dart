// lib/core/services/lan_server_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/order.dart';
import 'event_bus.dart';
import 'local_db_service.dart';

final lanServerServiceProvider = Provider<LanServerService>((ref) {
  final s = LanServerService(ref.read(localDbServiceProvider));
  ref.onDispose(s.stop);
  return s;
});

class LanServerService {
  final LocalDbService _local;
  HttpServer? _server;
  // All connected kitchen WebSocket clients
  final Set<WebSocketChannel> _clients = {};
  static const int port = 8080;

  LanServerService(this._local);

  Future<void> start() async {
    if (_server != null) return;

    final router = Router()
      ..get('/ping', _ping)
      ..get('/ws', _handleWs)         // ← NEW: WebSocket upgrade endpoint
      ..get('/orders/pending', _getPendingOrders)
      ..patch('/orders/<orderId>/status', _updateOrderStatus);

    final handler =
        Pipeline().addMiddleware(_corsMiddleware()).addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    // Listen for new orders on the EventBus and push to all WS clients
    EventBus.instance.on(AppEvents.orderPlaced).listen((event) {
      _broadcast({'type': 'order_placed', 'payload': event.payload});
    });

    // Also push status changes so kitchen sees POS-side updates
    EventBus.instance.on(AppEvents.orderStatusChanged).listen((event) {
      _broadcast({'type': 'order_status_changed', 'payload': event.payload});
    });
  }

  Future<void> stop() async {
    for (final c in _clients) {
      c.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  bool get isRunning => _server != null;

  // ── WebSocket handler ──────────────────────────────────────────────────────

  Handler get _handleWs => webSocketHandler((WebSocketChannel ws, _) {
        _clients.add(ws);
        // Remove client when it disconnects
        ws.stream.listen(
          (_) {}, // kitchen doesn't send via WS (uses HTTP PATCH instead)
          onDone: () => _clients.remove(ws),
          onError: (_) => _clients.remove(ws),
          cancelOnError: true,
        );
      });

  void _broadcast(Map<String, dynamic> message) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(message);
    final dead = <WebSocketChannel>[];
    for (final c in _clients) {
      try {
        c.sink.add(encoded);
      } catch (_) {
        dead.add(c);
      }
    }
    _clients.removeAll(dead);
  }

  // ── REST handlers (unchanged) ──────────────────────────────────────────────

  Response _ping(Request req) =>
      Response.ok(jsonEncode({'status': 'ok', 'ts': DateTime.now().toIso8601String()}),
          headers: {'content-type': 'application/json'});

  Future<Response> _getPendingOrders(Request req) async {
    try {
      final businessId = req.url.queryParameters['business_id'] ?? '';
      final orders = await _local.getOrders(businessId);
      final pending = orders
          .where((o) =>
              o.status == OrderStatus.pending ||
              o.status == OrderStatus.preparing ||
              o.status == OrderStatus.ready)
          .toList();

      final json = pending
          .map((o) => {
                'id': o.id,
                'order_number': o.orderNumber,
                'table_id': o.tableId,
                'status': o.status.value,
                'created_at': o.createdAt.toIso8601String(),
                'items': o.items
                    .map((i) => {'product_name': i.product.name, 'quantity': i.quantity})
                    .toList(),
              })
          .toList();

      return Response.ok(jsonEncode(json),
          headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': '$e'}));
    }
  }

  Future<Response> _updateOrderStatus(Request req, String orderId) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final statusStr = body['status'] as String?;
      if (statusStr == null) {
        return Response.badRequest(body: jsonEncode({'error': 'status required'}));
      }
      final status = OrderStatusX.fromString(statusStr);
      await _local.markOrderStatus(orderId, status);

      // Push the change to all other WS clients immediately
      _broadcast({'type': 'order_status_changed', 'payload': {'order_id': orderId, 'status': statusStr}});

      return Response.ok(jsonEncode({'success': true}),
          headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': '$e'}));
    }
  }

  Middleware _corsMiddleware() => (Handler handler) => (Request req) async {
        if (req.method == 'OPTIONS') return Response.ok('', headers: _corsHeaders);
        return (await handler(req)).change(headers: _corsHeaders);
      };

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}