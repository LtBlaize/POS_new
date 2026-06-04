// lib/core/services/sync_queue_service.dart
//
// Change from original: process_payment replay now includes reference_number
// so offline GCash/Maya/Card payments sync correctly to Supabase.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:uuid/uuid.dart';
import 'connectivity_service.dart';
import 'local_db_service.dart';
import '../../features/auth/auth_provider.dart';
import '../models/order.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final syncCompleteProvider = StateProvider<DateTime?>((ref) => null);

final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  final service = SyncQueueService(ref);
  ref.onDispose(service.dispose);
  return service;
});

final pendingQueueCountProvider = StateProvider<int>((ref) => 0);
final isSyncingProvider = StateProvider<bool>((ref) => false);

// ── Constants ─────────────────────────────────────────────────────────────────

const int kMaxRetries = 5;

// ── Service ───────────────────────────────────────────────────────────────────

class SyncQueueService {
  final Ref _ref;
  ProviderSubscription<bool>? _onlineSub;
  bool _syncInProgress = false;

  SyncQueueService(this._ref);

  void init() {
    _onlineSub = _ref.listen<bool>(isOnlineProvider, (prev, next) async {
      if (next == true && prev == false) {
        await _refreshCount();
        await flushQueue();
      }
    });
    _refreshCount();
  }

  void dispose() {
    _onlineSub?.close();
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

      int synced = 0;
      for (final entry in pending) {
        final id = entry['id'] as int;
        final retries = entry['retries'] as int;
        if (retries >= kMaxRetries) continue;

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
          await _local.incrementRetry(id, e.toString());
        }
      }

      // Purge entries that have exhausted all retries
      await _purgeDeadEntries();

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

  Future<void> _purgeDeadEntries() async {
    final d = await _local.db;
    final deleted = await d.delete(
      'sync_queue',
      where: 'retries >= ?',
      whereArgs: [kMaxRetries],
    );
    if (deleted > 0) {
      debugPrint('[SyncQueue] Purged $deleted dead entries');
    }
  }

  // ── Replay dispatcher ───────────────────────────────────────────────────────

  Future<void> _replay(Map<String, dynamic> entry) async {
    final op = entry['operation'] as String;
    final payload =
        jsonDecode(entry['payload'] as String) as Map<String, dynamic>;
    final recordId = entry['record_id'] as String;

    switch (op) {
      case 'insert_order':
        await _replayInsertOrder(payload);

      case 'insert_order_items':
        await _replayInsertOrderItems(payload);

      case 'update_order_status':
        await _client.from('orders').update({
          'status': payload['status'],
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

      // FIX: was missing reference_number — offline GCash/Maya/Card payments
      // would sync without it, leaving the column NULL in Supabase.
      case 'process_payment':
        await _client.from('orders').update({
          'payment_method': payload['payment_method'],
          'amount_tendered': payload['amount_tendered'],
          'change_amount': payload['change_amount'],
          'reference_number': payload['reference_number'],
          'paid_at': payload['paid_at'],
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
          debugPrint(
              '[SyncQueue] Receipt $recordId already exists, skipping');
        } catch (_) {
          await _client.from('receipts').insert(payload);
        }

      case 'adjust_stock':
        // Check if this adjustment was already logged (idempotency)
        final existingLog = await _client
            .from('inventory_logs')
            .select('id')
            .eq('product_id', recordId)
            .eq('action', payload['action'] as String)
            .eq('notes', payload['notes'] ?? '')
            .gte('created_at', payload['performed_at'] ?? '')
            .maybeSingle();

        if (existingLog != null) {
          debugPrint('[SyncQueue] adjust_stock already applied, skipping');
          break;
        }

        final row = await _client
            .from('products')
            .select('stock_quantity')
            .eq('id', recordId)
            .single();
        final currentStock = row['stock_quantity'] as int;
        final delta = payload['quantity_change'] as int;
        final newStock = currentStock + delta;

        await _client.from('products').update({
          'stock_quantity': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

        await _client.from('inventory_logs').insert({
          'business_id': payload['business_id'],
          'product_id': recordId,
          'action': payload['action'],
          'quantity_change': delta,
          'quantity_before': currentStock,
          'quantity_after': newStock,
          'performed_by': payload['performed_by'],
          'notes': payload['notes'],
          'performed_at': payload['performed_at'],
        });

      case 'insert_kitchen_ticket':
        // Idempotency: skip if ticket already exists for this order
        final existing = await _client
            .from('kitchen_tickets')
            .select('id')
            .eq('order_id', payload['order_id'] as String)
            .maybeSingle();
        if (existing == null) {
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

          await _client
              .from('order_items')
              .delete()
              .eq('order_id', payload['order_id'] as String)
              .eq('product_id', payload['product_id'] as String);
        }

      case 'adjust_variant_stock':
        final existingVariantLog = await _client
            .from('inventory_logs')
            .select('id')
            .eq('product_id', payload['product_id'] as String)
            .eq('action', payload['action'] as String)
            .eq('notes', payload['notes'] ?? '')
            .maybeSingle();
        if (existingVariantLog != null) {
          debugPrint('[SyncQueue] adjust_variant_stock already applied, skipping');
          break;
        }
        final variantRow = await _client
            .from('product_variants')
            .select('stock_quantity')
            .eq('id', recordId)
            .single();
        final currentVariantStock = variantRow['stock_quantity'] as int;
        final variantDelta = payload['quantity_change'] as int;
        final newVariantStock = currentVariantStock + variantDelta;

        await _client.from('product_variants').update({
          'stock_quantity': newVariantStock,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

        await _client.from('inventory_logs').insert({
          'business_id': payload['business_id'],
          'product_id': payload['product_id'],
          'action': payload['action'],
          'quantity_change': variantDelta,
          'quantity_before': currentVariantStock,
          'quantity_after': newVariantStock,
          'performed_by': payload['performed_by'],
          'notes': payload['notes'],
        });

      case 'record_credit_payment':
        // Idempotency: skip if payment transaction already exists
        final existingPayment = await _client
            .from('credit_transactions')
            .select('id')
            .eq('id', payload['payment_tx_id'] as String)
            .maybeSingle();
        if (existingPayment != null) {
          debugPrint('[SyncQueue] record_credit_payment already synced, skipping');
          break;
        }

        final customerId = payload['customer_id'] as String;
        final amount = (payload['amount'] as num).toDouble();
        final paymentTxId = payload['payment_tx_id'] as String;

        // Insert payment transaction
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
            'settled_at': newRemaining == 0
                ? DateTime.now().toIso8601String()
                : null,
          }).eq('id', creditTxId);

          await _client.from('credit_settlements').insert({
            'payment_tx_id': paymentTxId,
            'credit_tx_id': creditTxId,
            'amount_applied': applied,
          });
        }

        // Update customer total_owed
        await _client.rpc('decrement_credit_owed', params: {
          'p_customer_id': customerId,
          'p_amount': amount,
        });

      case 'void_order':
        // Idempotency: skip if already cancelled
        final orderRow = await _client
            .from('orders')
            .select('status')
            .eq('id', payload['order_id'] as String)
            .maybeSingle();
        if (orderRow == null ||
            orderRow['status'] == OrderStatus.cancelled.value) break;

        final voidedAt = payload['voided_at'] as String;
        final voidedById = payload['voided_by_staff_id'] as String;
        final reason = payload['reason'] as String;

        await _client.from('orders').update({
          'status': 'cancelled',
          'notes': reason,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', payload['order_id'] as String);

        final items =
            (payload['items'] as List).cast<Map<String, dynamic>>();
        for (final item in items) {
          await _client.from('void_order_items').insert({
            'id': const Uuid().v4(),
            'order_id': payload['order_id'],
            'product_id': item['product_id'],
            'product_name': item['product_name'],
            'unit_price': item['unit_price'],
            'quantity': item['quantity'],
            'subtotal': item['subtotal'],
            'reason': reason,
            'voided_by_staff_id': voidedById,
            'voided_by_staff_name': payload['voided_by_staff_name'],
            'voided_at': voidedAt,
          });
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

      case 'add_staff':
        await _client.from('staff_members').insert(payload);

      case 'update_staff':
        await _client
            .from('staff_members')
            .update(payload)
            .eq('id', recordId);

      case 'delete_staff':
        await _client
            .from('staff_members')
            .update({'is_active': false}).eq('id', recordId);

      default:
        debugPrint('[SyncQueue] Unknown operation: $op — skipping');
    }
  }

  Future<void> _replayInsertOrder(Map<String, dynamic> payload) async {
    try {
      await _client
          .from('orders')
          .select('id')
          .eq('id', payload['id'])
          .single();
      await _local.markOrderSynced(payload['id'] as String);
      return;
    } catch (_) {}

    final items =
        (payload['items'] as List).cast<Map<String, dynamic>>();
    final orderPayload = Map<String, dynamic>.from(payload)
      ..remove('items');

    await _client.from('orders').insert(orderPayload);
    if (items.isNotEmpty) {
      await _client.from('order_items').insert(items);
    }
    await _local.markOrderSynced(payload['id'] as String);
  }

  Future<void> _replayInsertOrderItems(
      Map<String, dynamic> payload) async {
    final items =
        (payload['items'] as List).cast<Map<String, dynamic>>();
    if (items.isNotEmpty) {
      await _client.from('order_items').upsert(items);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _refreshCount() async {
    final count = await _local.pendingQueueCount();
    _ref.read(pendingQueueCountProvider.notifier).state = count;
  }
}