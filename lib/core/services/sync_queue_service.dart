// lib/core/services/sync_queue_service.dart
//
// Stock adjustments (adjust_stock / adjust_variant_stock) now replay through
// the Postgres function apply_stock_change(), which checks the idempotency
// key, updates stock and writes the inventory log in ONE transaction. A failed
// log insert can no longer leave a stock change behind, so retries are safe.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'connectivity_service.dart';
import 'local_db_service.dart';
import 'image_storage_service.dart';
import '../../features/auth/auth_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final syncCompleteProvider = StateProvider<DateTime?>((ref) => null);
final shiftsReconciledProvider = StateProvider<DateTime?>((ref) => null);

final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  final service = SyncQueueService(ref);
  service.init();
  ref.onDispose(service.dispose);
  return service;
});

final pendingQueueCountProvider = StateProvider<int>((ref) => 0);
final failedQueueCountProvider = StateProvider<int>((ref) => 0);
final isSyncingProvider = StateProvider<bool>((ref) => false);

// ── Constants / helpers ───────────────────────────────────────────────────────

/// True for connectivity failures (not business-rule failures).
bool isNetworkError(Object e) {
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('TimeoutException') ||
      s.contains('Connection closed') ||
      s.contains('Connection reset');
}

const int kMaxRetries = 5;

// ── Service ───────────────────────────────────────────────────────────────────

class SyncQueueService {
  final Ref _ref;
  ProviderSubscription<bool>? _onlineSub;
  bool _syncInProgress = false;
  Timer? _retryTimer;

  SyncQueueService(this._ref);

  void init() {
    _onlineSub = _ref.listen<bool>(isOnlineProvider, (prev, next) async {
      if (next == true && prev == false) {
        await _refreshCount();
        await flushQueue();
      }
    });
    _retryTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_ref.read(isOnlineProvider) &&
          _ref.read(pendingQueueCountProvider) > 0) {
        await flushQueue();
      }
    });
    _refreshCount();
    _refreshFailedCount();
    // Flush any queued entries that survived the last session.
    Future.microtask(() async {
      final isOnline = _ref.read(isOnlineProvider);
      if (isOnline) {
        debugPrint('[SyncQueue] Online at startup — flushing queue');
        await flushQueue();
      }
    });
  }

  void dispose() {
    _onlineSub?.close();
    _retryTimer?.cancel();
  }

  SupabaseClient get _client => _ref.read(supabaseClientProvider);
  LocalDbService get _local => _ref.read(localDbServiceProvider);

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> enqueue({
    required String operation,
    required String tableName,
    required String recordId,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? const Uuid().v4();
    await _local.enqueue(
      operation: operation,
      tableName: tableName,
      recordId: recordId,
      payload: {...payload, '_idempotency_key': key},
    );
    await _refreshCount();
  }

  Future<void> flushQueue() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    _ref.read(isSyncingProvider.notifier).state = true;

    try {
      final pending = await _local.getPendingQueue();
      debugPrint('[SyncQueue] Flushing ${pending.length} item(s)');

      // Entries sharing a conflict key stay sequential in queue order;
      // different keys run in parallel.
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final entry in pending) {
        if ((entry['retries'] as int) >= kMaxRetries) continue;
        groups.putIfAbsent(_conflictKey(entry), () => []).add(entry);
      }

      final results = await Future.wait(groups.values.map(_flushGroup));
      final synced = results.fold<int>(0, (a, b) => a + b);

      await _markDeadEntries();
      await _refreshFailedCount();

      if (synced > 0) {
        _ref.read(syncCompleteProvider.notifier).state = DateTime.now();
        debugPrint('[SyncQueue] Synced $synced item(s) successfully');
      }
    } finally {
      _syncInProgress = false;
      _ref.read(isSyncingProvider.notifier).state = false;
      await _refreshCount();
    }
  }

  String _conflictKey(Map<String, dynamic> entry) {
    final op = entry['operation'] as String;
    final recordId = entry['record_id'] as String;
    switch (op) {
      case 'insert_order':
      case 'insert_order_items':
      case 'update_order_status':
      case 'process_payment':
      case 'process_split_payment':
      case 'append_order_items':
        // recordId is the order id for all of these.
        return 'order:$recordId';
      case 'insert_receipt':
      case 'void_order_item':
      case 'void_order':
      case 'insert_kitchen_ticket':
        final payload =
            jsonDecode(entry['payload'] as String) as Map<String, dynamic>;
        final orderId = payload['order_id'] as String?;
        return orderId != null ? 'order:$orderId' : 'misc:$recordId';
      case 'upsert_shift':
        return 'shift:$recordId';
      case 'adjust_stock':
        return 'product:$recordId';
      case 'adjust_variant_stock':
        return 'variant:$recordId';
      case 'record_credit_payment':
        final payload =
            jsonDecode(entry['payload'] as String) as Map<String, dynamic>;
        return 'credit:${payload['customer_id']}';
      case 'add_staff':
      case 'update_staff':
      case 'delete_staff':
        return 'staff:$recordId';
      default:
        return 'misc:$recordId';
    }
  }

  Future<int> _flushGroup(List<Map<String, dynamic>> entries) async {
    int synced = 0;
    for (final entry in entries) {
      final id = entry['id'] as int;
      final retries = entry['retries'] as int;
      try {
        if (retries > 0) {
          final backoffSeconds = 1 << retries; // 2, 4, 8, 16 seconds
          await Future.delayed(Duration(seconds: backoffSeconds));
        }
        await _replay(entry);
        await _local.dequeue(id);
        synced++;
      } catch (e) {
        debugPrint('[SyncQueue] Entry $id failed: $e');

        // Plan-limit rejections never succeed on retry: dead-letter now.
        final limitMessage = _planLimitMessage(e);
        if (limitMessage != null) {
          await _local.incrementRetry(id, limitMessage);
          await _local.markQueueDead(id);
          await _refreshFailedCount();
          continue;
        }

        // Network down is not the entry's fault: don't burn a retry.
        if (isNetworkError(e)) break;

        // Expired token after a long offline spell: refresh, don't burn a
        // retry. The next flush (60s timer) picks the entry up again.
        final s = e.toString();
        if (s.contains('JWT expired') || s.contains('PGRST301')) {
          try {
            await _client.auth.refreshSession();
          } catch (_) {}
          break;
        }

        await _local.incrementRetry(id, e.toString());
        // Later entries in this group would likely fail for the same reason.
        break;
      }
    }
    return synced;
  }

  Future<void> _markDeadEntries() async {
    final pending = await _local.getPendingQueue();
    final dead = pending.where((e) => (e['retries'] as int) >= kMaxRetries);
    for (final entry in dead) {
      await _local.markQueueDead(entry['id'] as int);
    }
    if (dead.isNotEmpty) {
      debugPrint(
          '[SyncQueue] Dead-lettered ${dead.length} entr${dead.length == 1 ? 'y' : 'ies'}');
    }
  }

  /// Re-queues a dead-lettered entry and immediately attempts a flush.
  Future<void> retryFailedEntry(int queueId) async {
    await _local.retryQueueEntry(queueId);
    await _refreshFailedCount();
    await _refreshCount();
    await flushQueue();
  }

  Future<List<Map<String, dynamic>>> getFailedEntries() =>
      _local.getFailedQueue();

  /// Permanently removes a dead-lettered entry.
  Future<void> discardFailedEntry(int queueId) async {
    await _local.dequeue(queueId);
    await _refreshFailedCount();
  }

  // ── Replay dispatcher ───────────────────────────────────────────────────────

  Future<void> _replay(Map<String, dynamic> entry) async {
    final op = entry['operation'] as String;
    final payload =
        jsonDecode(entry['payload'] as String) as Map<String, dynamic>;
    // Internal bookkeeping only. Never send to Supabase as a column.
    final idemKey = payload.remove('_idempotency_key') as String?;
    final recordId = entry['record_id'] as String;

    switch (op) {
      case 'insert_order':
        await _replayInsertOrder(payload);

      case 'insert_order_items':
        await _replayInsertOrderItems(payload);

      case 'append_order_items':
        await replayAppendOrderItems(payload);

      case 'update_order_status':
        await _client.from('orders').update({
          'status': payload['status'],
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

      case 'process_payment':
        await _client.from('orders').update({
          'payment_method': payload['payment_method'],
          'amount_tendered': payload['amount_tendered'],
          'change_amount': payload['change_amount'],
          'reference_number': payload['reference_number'],
          'paid_at': payload['paid_at'],
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

      case 'process_split_payment':
        final payments =
            (payload['payments'] as List).cast<Map<String, dynamic>>();
        // Idempotency: skip legs already present (checked by id).
        final existingIds = await _client
            .from('order_payments')
            .select('id')
            .eq('order_id', recordId);
        final existing =
            (existingIds as List).map((r) => r['id'] as String).toSet();
        final toInsert =
            payments.where((p) => !existing.contains(p['id'])).toList();
        if (toInsert.isNotEmpty) {
          await _client.from('order_payments').insert(toInsert);
        }
        await _client.from('orders').update({
          'payment_method': payload['primary_method'],
          'amount_tendered': payload['amount_tendered'],
          'change_amount': payload['change_amount'],
          'is_split_payment': true,
          'paid_at': payload['paid_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

      case 'insert_receipt':
        // Idempotency: skip if receipt already exists
        try {
          await _client
              .from('receipts')
              .select('id')
              .eq('receipt_number', recordId)
              .single();
          debugPrint('[SyncQueue] Receipt $recordId already exists, skipping');
        } catch (_) {
          await _client.from('receipts').insert(payload);
        }

      // Atomic: idempotency check + stock update + log insert in one
      // transaction inside apply_stock_change().
      case 'adjust_stock':
      case 'adjust_variant_stock':
        final isVariant = op == 'adjust_variant_stock';
        await _client.rpc('apply_stock_change', params: {
          'p_business_id': payload['business_id'],
          'p_product_id': isVariant ? payload['product_id'] : recordId,
          'p_variant_id': isVariant ? recordId : null,
          'p_delta': payload['quantity_change'],
          'p_action': payload['action'],
          'p_performed_by': payload['performed_by'],
          'p_notes': payload['notes'],
          'p_idempotency_key': idemKey,
        });

      case 'upload_product_image':
        final productId = recordId;
        final localPath = payload['local_path'] as String;
        final bytes = await ProductImagePipeline.readLocalBytes(localPath);
        final remotePath = '${payload['business_id']}/$productId.jpg';
        final storage = _ref.read(imageStorageServiceProvider);
        final url = await storage.upload(bytes, remotePath);

        await _client
            .from('products')
            .update({'image_url': url}).eq('id', productId);
        await _local.updateProductImageUrl(productId, url);

      case 'insert_kitchen_ticket':
        // Idempotency: one ticket per (order, round)
        final ticketRound = (payload['round'] as int?) ?? 1;
        final existingTicket = await _client
            .from('kitchen_tickets')
            .select('id')
            .eq('order_id', payload['order_id'] as String)
            .eq('round', ticketRound)
            .limit(1);
        if ((existingTicket as List).isEmpty) {
          await _client.from('kitchen_tickets').insert(payload);
        }

      case 'void_order_item':
        // Idempotency: skip if void record already exists
        final existingVoid = await _client
            .from('void_order_items')
            .select('id')
            .eq('id', recordId)
            .maybeSingle();
        if (existingVoid == null) {
          final voidPayload = Map<String, dynamic>.from(payload)
            ..remove('track_inventory')
            ..remove('current_stock')
            ..remove('business_id');
          await _client.from('void_order_items').insert(voidPayload);

          var find = _client
              .from('order_items')
              .select('id')
              .eq('order_id', payload['order_id'] as String)
              .eq('product_id', payload['product_id'] as String);
          if (payload['variant_id'] != null) {
            find = find.eq('variant_id', payload['variant_id'] as String);
          }
          final target = await find.limit(1).maybeSingle();
          if (target != null) {
            await _client
                .from('order_items')
                .delete()
                .eq('id', target['id'] as String);
          }
          await _recomputeOrderTotals(payload['order_id'] as String);
        }

      case 'record_credit_payment':
        // Idempotency: skip if payment transaction already exists
        final existingPayment = await _client
            .from('credit_transactions')
            .select('id')
            .eq('id', payload['payment_tx_id'] as String)
            .maybeSingle();
        if (existingPayment != null) {
          debugPrint(
              '[SyncQueue] record_credit_payment already synced, skipping');
          break;
        }

        final customerId = payload['customer_id'] as String;
        final amount = (payload['amount'] as num).toDouble();
        final paymentTxId = payload['payment_tx_id'] as String;

        await _client.from('credit_transactions').insert({
          'id': paymentTxId,
          'customer_id': customerId,
          'business_id': payload['business_id'],
          'type': 'payment',
          'amount': amount,
          'amount_remaining': 0,
          'is_settled': true,
          'note': payload['note'],
          'created_at': payload['created_at'],
        });

        // FIFO settlement against unsettled credits
        final unsettled = await _client
            .from('credit_transactions')
            .select()
            .eq('customer_id', customerId)
            .eq('type', 'credit')
            .eq('is_settled', false)
            .order('created_at', ascending: true);

        double remaining = amount;
        for (final row in unsettled as List) {
          if (remaining <= 0) break;
          final creditTxId = row['id'] as String;
          final amtRemaining = (row['amount_remaining'] as num).toDouble();
          final applied = remaining >= amtRemaining ? amtRemaining : remaining;
          final newRemaining = amtRemaining - applied;
          remaining -= applied;

          await _client.from('credit_transactions').update({
            'amount_remaining': newRemaining,
            'is_settled': newRemaining == 0,
            'settled_at':
                newRemaining == 0 ? DateTime.now().toIso8601String() : null,
          }).eq('id', creditTxId);

          await _client.from('credit_settlements').insert({
            'payment_tx_id': paymentTxId,
            'credit_tx_id': creditTxId,
            'amount_applied': applied,
          });
        }

        await _client.rpc('decrement_credit_owed', params: {
          'p_customer_id': customerId,
          'p_amount': amount,
        });

      case 'void_order':
        final orderRow = await _client
            .from('orders')
            .select('status')
            .eq('id', payload['order_id'] as String)
            .maybeSingle();
        if (orderRow == null) break;

        final voidedAt = payload['voided_at'] as String;
        final voidedById = payload['voided_by_staff_id'] as String;
        final reason = payload['reason'] as String;

        await _client.from('orders').update({
          'status': 'cancelled',
          'notes': reason,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', payload['order_id'] as String);

        // Upsert by id: safe to re-run after a partial failure.
        final items = (payload['items'] as List).cast<Map<String, dynamic>>();
        for (final item in items) {
          await _client.from('void_order_items').upsert({
            'id': item['id'],
            'order_id': payload['order_id'],
            'product_id': item['product_id'],
            'product_name': item['product_name'],
            'unit_price': item['unit_price'],
            'quantity': item['quantity'],
            'subtotal': item['subtotal'],
            'promo_id': item['promo_id'],
            'promo_group_id': item['promo_group_id'],
            'reason': reason,
            'voided_by_staff_id': voidedById,
            'voided_by_staff_name': payload['voided_by_staff_name'],
            'voided_at': voidedAt,
          }, onConflict: 'id');
          await _local.markVoidSynced(item['id'] as String);
        }

        await _client
            .from('receipts')
            .update({
              'is_voided': true,
              'voided_at': voidedAt,
              'voided_by': voidedById,
              'void_reason': reason,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('order_id', payload['order_id'] as String)
            .eq('is_voided', false);

      case 'upsert_shift':
        try {
          await _client
              .from('cashier_shifts')
              .upsert(payload, onConflict: 'id');
        } on PostgrestException catch (e) {
          final dupOpen = e.code == '23505' &&
              e.message.contains('idx_one_open_shift_per_staff');
          if (!dupOpen) rethrow;
          // Staff already has an open shift on the server: adopt it.
          final server = await _client
              .from('cashier_shifts')
              .select()
              .eq('staff_id', payload['staff_id'] as String)
              .eq('status', 'open')
              .limit(1)
              .maybeSingle();
          if (server == null) rethrow;
          await _local.adoptServerShift(
              localId: recordId, server: Map<String, dynamic>.from(server));
          _ref.read(shiftsReconciledProvider.notifier).state = DateTime.now();
        }

      case 'insert_audit_log':
        await _client.from('audit_logs').upsert(payload, onConflict: 'id');

      case 'add_staff':
        await _client.from('staff_members').insert(payload);

      case 'update_staff':
        await _client.from('staff_members').update(payload).eq('id', recordId);

      case 'delete_staff':
        await _client
            .from('staff_members')
            .update({'is_active': false}).eq('id', recordId);

      default:
        debugPrint('[SyncQueue] Unknown operation: $op — skipping');
    }
  }

  // ── Order helpers ───────────────────────────────────────────────────────────

  /// Single implementation used by both the live online path and queue replay.
  /// Idempotent: rows are keyed by client-generated ids, and totals are
  /// recomputed from the rows rather than incremented.
  Future<void> replayAppendOrderItems(Map<String, dynamic> payload) async {
    final orderId = payload['order_id'] as String;
    final rows = (payload['items'] as List).cast<Map<String, dynamic>>();
    final ids = rows.map((r) => r['id'] as String).toList();

    final existing =
        await _client.from('order_items').select('id').inFilter('id', ids);
    final have = (existing as List).map((r) => r['id'] as String).toSet();
    final fresh = <Map<String, dynamic>>[
      for (final r in rows)
        if (!have.contains(r['id'])) {...r, 'order_id': orderId},
    ];
    if (fresh.isNotEmpty) await _client.from('order_items').insert(fresh);

    final all = await _client
        .from('order_items')
        .select('subtotal')
        .eq('order_id', orderId);
    final subtotal = (all as List)
        .fold<double>(0, (s, r) => s + (r['subtotal'] as num).toDouble());

    final order = await _client
        .from('orders')
        .select('discount_amount, tip_amount, status, paid_at')
        .eq('id', orderId)
        .single();
    final taxRate = (payload['tax_rate'] as num?)?.toDouble() ?? 0.0;
    final tax = subtotal * taxRate;
    final discount = (order['discount_amount'] as num).toDouble();
    final tip = (order['tip_amount'] as num?)?.toDouble() ?? 0.0;
    final reopen = payload['reopen_for_kitchen'] == true &&
        order['paid_at'] == null &&
        order['status'] != 'cancelled';

    await _client.from('orders').update({
      'subtotal': subtotal,
      'tax_amount': tax,
      'total_amount': subtotal + tax - discount + tip,
      if (reopen) 'status': 'pending',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
  }

  Future<void> _recomputeOrderTotals(String orderId) async {
    final remaining = await _client
        .from('order_items')
        .select('subtotal')
        .eq('order_id', orderId) as List;
    final now = DateTime.now().toIso8601String();
    if (remaining.isEmpty) {
      await _client
          .from('orders')
          .update({'status': 'cancelled', 'updated_at': now}).eq('id', orderId);
      return;
    }
    final newSubtotal = remaining.fold<double>(
        0, (s, r) => s + (r['subtotal'] as num).toDouble());
    final o = await _client
        .from('orders')
        .select('tax_amount, discount_amount, subtotal, tip_amount')
        .eq('id', orderId)
        .single();
    final oldSub = (o['subtotal'] as num).toDouble();
    final taxRate =
        oldSub > 0 ? (o['tax_amount'] as num).toDouble() / oldSub : 0.0;
    final newTax = newSubtotal * taxRate;
    final newDiscount =
        (o['discount_amount'] as num).toDouble().clamp(0.0, newSubtotal);
    final tip = (o['tip_amount'] as num?)?.toDouble() ?? 0.0;
    await _client.from('orders').update({
      'subtotal': newSubtotal,
      'tax_amount': newTax,
      'discount_amount': newDiscount,
      'total_amount': newSubtotal + newTax - newDiscount + tip,
      'updated_at': now,
    }).eq('id', orderId);
  }

  Future<void> _replayInsertOrder(Map<String, dynamic> payload) async {
    final orderId = payload['id'] as String;
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
    final orderPayload = Map<String, dynamic>.from(payload)..remove('items');

    await _client
        .from('orders')
        .upsert(orderPayload, onConflict: 'id', ignoreDuplicates: true);

    final existing = await _client
        .from('order_items')
        .select('id')
        .eq('order_id', orderId)
        .limit(1);
    if ((existing as List).isEmpty && items.isNotEmpty) {
      await _client.from('order_items').insert([
        for (final i in items) {...i, 'order_id': orderId},
      ]);
    }

    await _local.markOrderSynced(orderId);
  }

  Future<void> _replayInsertOrderItems(Map<String, dynamic> payload) async {
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
    if (items.isNotEmpty) {
      await _client.from('order_items').upsert(items);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Maps a known DB-level plan-limit trigger rejection to a friendly message.
  /// Returns null for any other error, so normal retry/backoff applies.
  String? _planLimitMessage(Object error) {
    final msg = error.toString();
    if (msg.contains('staff_limit_exceeded')) {
      return 'This staff account couldn\'t be added — your plan\'s staff limit was reached before this synced. Remove a staff member or upgrade your plan, then re-add them from Settings.';
    }
    if (msg.contains('promo_limit_exceeded')) {
      return 'This promo couldn\'t be activated — your plan\'s active promo limit was reached before this synced. Deactivate another promo or upgrade your plan.';
    }
    if (msg.contains('table_limit_exceeded')) {
      return 'This table couldn\'t be added — your plan\'s table limit was reached before this synced. Upgrade your plan to add more tables.';
    }
    return null;
  }

  Future<void> _refreshCount() async {
    final count = await _local.pendingQueueCount();
    _ref.read(pendingQueueCountProvider.notifier).state = count;
  }

  Future<void> _refreshFailedCount() async {
    final count = await _local.failedQueueCount();
    _ref.read(failedQueueCountProvider.notifier).state = count;
  }
}