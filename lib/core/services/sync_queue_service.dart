// lib/core/services/sync_queue_service.dart
//
// Change from original: process_payment replay now includes reference_number
// so offline GCash/Maya/Card payments sync correctly to Supabase.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'local_db_service.dart';
import '../../features/auth/auth_provider.dart';

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
  }) async {
    await _local.enqueue(
      operation: operation,
      tableName: tableName,
      recordId: recordId,
      payload: payload,
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