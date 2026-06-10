// lib/core/services/credit_service.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/credit.dart';
import 'connectivity_service.dart';
import 'local_db_service.dart';

final creditServiceProvider = Provider<CreditService>((ref) {
  return CreditService(
    ref.watch(localDbServiceProvider),
    Supabase.instance.client,
    ref,
  );
});

class CreditService {
  final LocalDbService _db;
  final SupabaseClient _supabase;
  final Ref _ref;

  const CreditService(this._db, this._supabase, this._ref);

  String _uuid() => const Uuid().v4();

  bool get _isOnline => _ref.read(isOnlineProvider);

  // ── Customers ──────────────────────────────────────────────────────────────

  Future<List<CreditCustomer>> getCustomers(String businessId) async {
    try {
      final rows = await _supabase
          .from('credit_customers')
          .select()
          .eq('business_id', businessId)
          .order('name');
      final customers = rows.map(_customerFromMap).toList();
      await _cacheCustomers(customers);
      return customers;
    } catch (_) {
      final d = await _db.db;
      final rows = await d.query(
        'credit_customers',
        where: 'business_id = ?',
        whereArgs: [businessId],
        orderBy: 'name ASC',
      );
      return rows.map(_customerFromMap).toList();
    }
  }

  Future<void> _cacheCustomers(List<CreditCustomer> customers) async {
    final d = await _db.db;
    final batch = d.batch();
    for (final c in customers) {
      batch.insert('credit_customers', _customerToLocalRow(c),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<CreditCustomer?> findCustomerByPhone(
      String businessId, String phone) async {
    try {
      final rows = await _supabase
          .from('credit_customers')
          .select()
          .eq('business_id', businessId)
          .eq('phone', phone)
          .limit(1);
      if (rows.isEmpty) return null;
      return _customerFromMap(rows.first);
    } catch (_) {
      final d = await _db.db;
      final rows = await d.query(
        'credit_customers',
        where: 'business_id = ? AND phone = ?',
        whereArgs: [businessId, phone],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _customerFromMap(rows.first);
    }
  }

  Future<CreditCustomer> createCustomer({
    required String businessId,
    required String name,
    required String phone,
  }) async {
    final row = await _supabase
        .from('credit_customers')
        .insert({
          'business_id': businessId,
          'name': name,
          'phone': phone,
          'total_owed': 0.0,
        })
        .select()
        .single();

    final customer = _customerFromMap(row);
    final d = await _db.db;
    await d.insert('credit_customers', _customerToLocalRow(customer),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return customer;
  }

  // ── Transactions ───────────────────────────────────────────────────────────

  Future<List<CreditTransaction>> getTransactions(String customerId) async {
    try {
      final rows = await _supabase
          .from('credit_transactions')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return rows.map(_txFromMap).toList();
    } catch (_) {
      final d = await _db.db;
      final rows = await d.query(
        'credit_transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at DESC',
      );
      return rows.map(_txFromMap).toList();
    }
  }

  /// Add utang — called at checkout
  Future<void> addCredit({
    required String customerId,
    required String businessId,
    required double amount,
    String? note,
    String? orderId,
  }) async {
    final txRow = await _supabase
        .from('credit_transactions')
        .insert({
          'customer_id': customerId,
          'business_id': businessId,
          'type': 'credit',
          'amount': amount,
          'amount_remaining': amount,
          'is_settled': false,
          'note': note,
          'order_id': orderId,
        })
        .select()
        .single();

    await _supabase.rpc('increment_credit_owed', params: {
      'p_customer_id': customerId,
      'p_amount': amount,
    });

    // Mirror to SQLite
    final d = await _db.db;
    await d.transaction((txn) async {
      await txn.insert('credit_transactions', {
        'id': txRow['id'],
        'customer_id': customerId,
        'business_id': businessId,
        'type': 'credit',
        'amount': amount,
        'amount_remaining': amount,
        'is_settled': 0,
        'note': note,
        'order_id': orderId,
        'created_at': txRow['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawUpdate(
        'UPDATE credit_customers SET total_owed = total_owed + ?, updated_at = ? WHERE id = ?',
        [amount, DateTime.now().toIso8601String(), customerId],
      );
    });
  }

  /// Record payment — FIFO online, simple offline with sync queue.
  Future<PaymentResult> recordPayment({
    required String customerId,
    required String businessId,
    required double amount,
    String? note,
  }) async {
    final now = DateTime.now();
    // Pre-generate ID so both online and offline paths use the same one,
    // making the sync queue replay idempotent via upsert.
    final paymentTxId = _uuid();

    // ── Offline fast path ───────────────────────────────────────────────────
    //
    // Why check online here instead of using isOnlineProvider?
    // CreditService is a plain class with no Ref — it doesn't have access
    // to Riverpod providers. A lightweight probe is the cleanest option.
    if (!_isOnline) {
      // 1. Save payment locally so the cashier sees it immediately
      await _db.insertCreditTransaction(
        id: paymentTxId,
        customerId: customerId,
        businessId: businessId,
        type: 'payment',
        amount: amount,
        note: note,
        createdAt: now.toIso8601String(),
      );

      // 2. Reduce local total_owed so the UI reflects the payment
      await _db.updateCreditCustomerOwed(
        customerId: customerId,
        delta: -amount,
      );

      // 3. Queue for sync when back online.
      //    The replay handler in sync_queue_service.dart will do the full
      //    FIFO settlement against Supabase when connectivity returns.
      final d = await _db.db;
      await d.insert('sync_queue', {
        'operation': 'record_credit_payment',
        'table_name': 'credit_transactions',
        'record_id': paymentTxId,
        'payload': jsonEncode({
          'payment_tx_id': paymentTxId,
          'customer_id': customerId,
          'business_id': businessId,
          'amount': amount,
          'note': note,
          'created_at': now.toIso8601String(),
        }),
        'created_at': now.toIso8601String(),
        'retries': 0,
      });

      return PaymentResult(
        paymentTxId: paymentTxId,
        settledCredits: [],
        leftoverCredit: 0,
      );
    }

    // ── Online path ─────────────────────────────────────────────────────────

    // 1. Fetch all unsettled credit transactions, oldest first (FIFO)
    final unsettled = await _supabase
        .from('credit_transactions')
        .select()
        .eq('customer_id', customerId)
        .eq('type', 'credit')
        .eq('is_settled', false)
        .order('created_at', ascending: true);

    // 2. Insert the payment transaction using the pre-generated ID
    //    so the offline and online records always share the same UUID.
    final paymentRow = await _supabase
        .from('credit_transactions')
        .insert({
          'id': paymentTxId,
          'customer_id': customerId,
          'business_id': businessId,
          'type': 'payment',
          'amount': amount,
          'amount_remaining': 0,
          'is_settled': true,
          'note': note,
        })
        .select()
        .single();

    // 3. Apply FIFO settlement
    double remaining = amount;
    final settlements = <Map<String, dynamic>>[];
    final creditUpdates = <Map<String, dynamic>>[];

    for (final row in unsettled) {
      if (remaining <= 0) break;

      final creditTxId = row['id'] as String;
      final amountRemaining = (row['amount_remaining'] as num).toDouble();
      final applied =
          remaining >= amountRemaining ? amountRemaining : remaining;
      final newRemaining = amountRemaining - applied;
      remaining -= applied;

      settlements.add({
        'payment_tx_id': paymentTxId,
        'credit_tx_id': creditTxId,
        'amount_applied': applied,
      });

      creditUpdates.add({
        'id': creditTxId,
        'amount_remaining': newRemaining,
        'is_settled': newRemaining == 0,
        'settled_at':
            newRemaining == 0 ? DateTime.now().toIso8601String() : null,
      });
    }

    // 4. Batch-update each affected credit transaction in Supabase
    for (final update in creditUpdates) {
      await _supabase
          .from('credit_transactions')
          .update({
            'amount_remaining': update['amount_remaining'],
            'is_settled': update['is_settled'],
            'settled_at': update['settled_at'],
          })
          .eq('id', update['id']);
    }

    // 5. Insert settlement records
    if (settlements.isNotEmpty) {
      await _supabase.from('credit_settlements').insert(settlements);
    }

    // 6. Update customer total_owed — only deduct what was actually applied
    final actuallyApplied = amount - remaining;
    if (actuallyApplied > 0) {
      await _supabase.rpc('decrement_credit_owed', params: {
        'p_customer_id': customerId,
        'p_amount': actuallyApplied,
      });
    }

    // 7. Mirror payment to SQLite
    final d = await _db.db;
    await d.transaction((txn) async {
      await txn.insert('credit_transactions', {
        'id': paymentTxId,
        'customer_id': customerId,
        'business_id': businessId,
        'type': 'payment',
        'amount': amount,
        'note': note,
        'order_id': null,
        'created_at': paymentRow['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawUpdate(
        'UPDATE credit_customers SET total_owed = MAX(0, total_owed - ?), updated_at = ? WHERE id = ?',
        [amount, DateTime.now().toIso8601String(), customerId],
      );
    });

    return PaymentResult(
      paymentTxId: paymentTxId,
      settledCredits: creditUpdates
          .where((u) => u['is_settled'] == true)
          .map((u) => u['id'] as String)
          .toList(),
      leftoverCredit: remaining,
    );
  }

  // ── Mappers ────────────────────────────────────────────────────────────────

  CreditCustomer _customerFromMap(Map<String, dynamic> r) => CreditCustomer(
        id: r['id'] as String,
        businessId: r['business_id'] as String,
        name: r['name'] as String,
        phone: r['phone'] as String,
        totalOwed: (r['total_owed'] as num).toDouble(),
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  Map<String, dynamic> _customerToLocalRow(CreditCustomer c) => {
        'id': c.id,
        'business_id': c.businessId,
        'name': c.name,
        'phone': c.phone,
        'total_owed': c.totalOwed,
        'created_at': c.createdAt.toIso8601String(),
        'updated_at': c.updatedAt.toIso8601String(),
      };

  CreditTransaction _txFromMap(Map<String, dynamic> r) => CreditTransaction(
        id: r['id'] as String,
        customerId: r['customer_id'] as String,
        businessId: r['business_id'] as String? ?? '',
        type: r['type'] == 'credit'
            ? CreditTxType.credit
            : CreditTxType.payment,
        amount: (r['amount'] as num).toDouble(),
        amountRemaining: r['amount_remaining'] != null
            ? (r['amount_remaining'] as num).toDouble()
            : null,
        isSettled: r['is_settled'] as bool? ?? false,
        settledAt: r['settled_at'] != null
            ? DateTime.parse(r['settled_at'] as String)
            : null,
        note: r['note'] as String?,
        orderId: r['order_id'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

/// Result of a payment operation
class PaymentResult {
  final String paymentTxId;
  final List<String> settledCredits;
  final double leftoverCredit;

  const PaymentResult({
    required this.paymentTxId,
    required this.settledCredits,
    required this.leftoverCredit,
  });
}