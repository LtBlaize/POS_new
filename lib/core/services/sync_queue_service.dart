// lib/core/services/sync_queue_service.dart
//
// Listens to isOnlineProvider. When online is restored, replays every pending
// entry in the sync_queue table against Supabase in FIFO order.
//
// Each entry has:
//   operation  → 'insert_order' | 'update_order_status' | 'process_payment'
//                'adjust_stock' | 'add_staff' | 'update_staff' | 'delete_staff'
//   table_name → informational (for logging)
//   record_id  → the PK of the affected row
//   payload    → JSON of all data needed to replay the call
//
// Failures are retried up to kMaxRetries times; after that the entry is kept
// for manual inspection (visible via pendingQueueCountProvider).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'local_db_service.dart';
import '../../features/auth/auth_provider.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
// Add this provider near the top with the others
final syncCompleteProvider = StateProvider<DateTime?>((ref) => null);
final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  final service = SyncQueueService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// How many items are waiting to sync — drives the badge in offline_banner.
final pendingQueueCountProvider = StateProvider<int>((ref) => 0);

/// True while a sync is in progress.
final isSyncingProvider = StateProvider<bool>((ref) => false);

// ── Constants ─────────────────────────────────────────────────────────────────

const int kMaxRetries = 5;

// ── Service ───────────────────────────────────────────────────────────────────

class SyncQueueService {
  final Ref _ref;
  ProviderSubscription<bool>? _onlineSub;
  bool _syncInProgress = false;

  SyncQueueService(this._ref);

  /// Call once from main() — starts listening for connectivity changes.
  void init() {
    _onlineSub = _ref.listen<bool>(isOnlineProvider, (prev, next) async {
      if (next == true && prev == false) {
        // Just came back online
        await _refreshCount();
        await flushQueue();
      }
    });
    // Update count on startup
    _refreshCount();
  }

  void dispose() {
    _onlineSub?.close();
  }

  SupabaseClient get _client => _ref.read(supabaseClientProvider);
  LocalDbService get _local => _ref.read(localDbServiceProvider);

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Add a mutation to the queue. Call this instead of direct Supabase calls
  /// when offline.
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

  /// Flush the queue immediately (also called automatically on reconnect).
  Future<void> flushQueue() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    _ref.read(isSyncingProvider.notifier).state = true;

    try {
      final pending = await _local.getPendingQueue();
      debugPrint('[SyncQueue] Flushing ${pending.length} item(s)');

      int synced = 0; // ← ADD
      for (final entry in pending) {
        final id = entry['id'] as int;
        final retries = entry['retries'] as int;
        if (retries >= kMaxRetries) continue;

        try {
          await _replay(entry);
          await _local.dequeue(id);
          synced++; // ← ADD
        } catch (e) {
          debugPrint('[SyncQueue] Entry $id failed: $e');
          await _local.incrementRetry(id, e.toString());
        }
      }

      // ← ADD: notify listeners that sync completed
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

  // ── Replay dispatcher ───────────────────────────────────────────────────────

  Future<void> _replay(Map<String, dynamic> entry) async {
    final op = entry['operation'] as String;
    final payload = jsonDecode(entry['payload'] as String) as Map<String, dynamic>;
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

      case 'process_payment':
        await _client.from('orders').update({
          'payment_method': payload['payment_method'],
          'amount_tendered': payload['amount_tendered'],
          'change_amount': payload['change_amount'],
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
            debugPrint('[SyncQueue] Receipt $recordId already exists, skipping');
          } catch (_) {
            // Not found — safe to insert
            await _client.from('receipts').insert(payload);
          }

      case 'adjust_stock':
        // Re-read current stock from Supabase first to avoid double-applying
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
        });

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

  Future<void> _replayInsertOrder(Map<String, dynamic> payload) async {
    // Check if order already synced (idempotency guard)
    try {
      await _client.from('orders').select('id').eq('id', payload['id']).single();
      // Already exists — mark local as synced and skip
      await _local.markOrderSynced(payload['id'] as String);
      return;
    } catch (_) {
      // Not found — safe to insert
    }

    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
    final orderPayload = Map<String, dynamic>.from(payload)..remove('items');

    await _client.from('orders').insert(orderPayload);
    if (items.isNotEmpty) {
      await _client.from('order_items').insert(items);
    }
    await _local.markOrderSynced(payload['id'] as String);
  }

  Future<void> _replayInsertOrderItems(Map<String, dynamic> payload) async {
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
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