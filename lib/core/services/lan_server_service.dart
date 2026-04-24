import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../models/order.dart';
import 'local_db_service.dart';

final lanServerServiceProvider = Provider<LanServerService>((ref) {
  return LanServerService(ref.read(localDbServiceProvider));
});

class LanServerService {
  final LocalDbService _local;
  HttpServer? _server;
  static const int port = 8080;

  LanServerService(this._local);

  Future<void> start() async {
    if (_server != null) return; // already running

    final router = Router()
      ..get('/ping', _ping)
      ..get('/orders/pending', _getPendingOrders)
      ..patch('/orders/<orderId>/status', _updateOrderStatus);

    final handler = Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
    );

    print('[LAN] Server listening on port $port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  bool get isRunning => _server != null;

  // ── Handlers ──────────────────────────────────────────────────────────────

  Response _ping(Request req) =>
      Response.ok(jsonEncode({'status': 'ok'}),
          headers: {'content-type': 'application/json'});

  Future<Response> _getPendingOrders(Request req) async {
    try {
      // Get businessId from query param — kitchen passes it on first connect
      final businessId = req.url.queryParameters['business_id'] ?? '';
      final orders = await _local.getOrders(businessId);

      final pending = orders
          .where((o) =>
              o.status == OrderStatus.pending ||
              o.status == OrderStatus.preparing)
          .toList();

      final json = pending
          .map((o) => {
                'id': o.id,
                'order_number': o.orderNumber,
                'table_id': o.tableId,
                'status': o.status.value,
                'created_at': o.createdAt.toIso8601String(),
                'items': o.items
                    .map((i) => {
                          'product_name': i.product.name,
                          'quantity': i.quantity,
                        })
                    .toList(),
              })
          .toList();

      return Response.ok(jsonEncode(json),
          headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<Response> _updateOrderStatus(Request req, String orderId) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final statusStr = body['status'] as String?;
      if (statusStr == null) {
        return Response.badRequest(
            body: jsonEncode({'error': 'status required'}));
      }

      final status = OrderStatusX.fromString(statusStr);

      // Update local DB
      await _local.markOrderStatus(orderId, status);

      return Response.ok(jsonEncode({'success': true}),
          headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}));
    }
  }

  // ── CORS (needed for web, harmless for desktop) ───────────────────────────

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request req) async {
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final res = await handler(req);
        return res.change(headers: _corsHeaders);
      };
    };
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}