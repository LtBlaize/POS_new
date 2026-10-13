// lib/core/services/credit_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/credit.dart';
import 'connectivity_service.dart';
import 'local_db_service.dart';
import 'sync_queue_service.dart';

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
    // Unsynced utang/payments exist: the server balance is stale, trust local.
    if (await _db.pendingQueueCount() > 0) {
      return _localCustomers(businessId);
    }
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

  Future<List<CreditCustomer>> _localCustomers(String businessId) async {
    final d = await _db.db;
    final rows = await d.query(
      'credit_customers',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(_customerFromMap).toList();
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
    final now = DateTime.now().toUtc();
    final customer = CreditCustomer(
      id: _uuid(),
      businessId: businessId,
      name: name,
      phone: phone,
      totalOwed: 0,
      createdAt: now,
      updatedAt: now,
    );
    final d = await _db.db;
    await d.insert('credit_customers', _customerToLocalRow(customer),
        conflictAlgorithm: ConflictAlgorithm.replace);

    final row = {
      'id': customer.id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
    };
    if (_isOnline) {
      try {
        await _supabase
            .from('credit_customers')
            .upsert(row, onConflict: 'id', ignoreDuplicates: true);
        return customer;
      } catch (e) {
        debugPrint('[Credit] createCustomer failed, queuing: $e');
      }
    }
    await _ref.read(syncQueueServiceProvider).enqueue(
          operation: 'upsert_credit_customer',
          tableName: 'credit_customers',
          recordId: customer.id,
          payload: row,
        );
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

  /// Add utang. Local first, then server (or queue). Idempotent on the tx id.
  Future<void> addCredit({
    required String customerId,
    required String businessId,
    required double amount,
    String? note,
    String? orderId,
  }) async {
    final txId = _uuid();
    final createdAt = DateTime.now().toUtc().toIso8601String();

    final d = await _db.db;
    final custRows = await d.query('credit_customers',
        where: 'id = ?', whereArgs: [customerId], limit: 1);
    await d.transaction((txn) async {
      await txn.insert('credit_transactions', {
        'id': txId,
        'customer_id': customerId,
        'business_id': businessId,
        'type': 'credit',
        'amount': amount,
        'amount_remaining': amount,
        'is_settled': 0,
        'note': note,
        'order_id': orderId,
        'created_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawUpdate(
        'UPDATE credit_customers SET total_owed = total_owed + ?, updated_at = ? WHERE id = ?',
        [amount, createdAt, customerId],
      );
    });

    if (_isOnline) {
      try {
        await _supabase.rpc('add_credit', params: {
          'p_id': txId,
          'p_customer_id': customerId,
          'p_business_id': businessId,
          'p_amount': amount,
          'p_note': note,
          'p_order_id': orderId,
          'p_created_at': createdAt,
        });
        return;
      } catch (e) {
        debugPrint('[Credit] add_credit failed, queuing: $e');
      }
    }

    final c = custRows.isEmpty ? null : custRows.first;
    await _ref.read(syncQueueServiceProvider).enqueue(
      operation: 'add_credit',
      tableName: 'credit_transactions',
      recordId: txId,
      payload: {
        'customer_id': customerId,
        'business_id': businessId,
        'amount': amount,
        'note': note,
        'order_id': orderId,
        'created_at': createdAt,
        // Lets the replay create the customer first if it isn't on the server.
        if (c != null)
          'customer': {
            'id': c['id'],
            'business_id': c['business_id'],
            'name': c['name'],
            'phone': c['phone'],
          },
      },
    );
  }

  /// Record a payment. Local first, then one atomic server call (or queue).
  Future<PaymentResult> recordPayment({
    required String customerId,
    required String businessId,
    required double amount,
    String? note,
  }) async {
    final paymentTxId = _uuid();
    final createdAt = DateTime.now().toUtc().toIso8601String();

    await _db.insertCreditTransaction(
      id: paymentTxId,
      customerId: customerId,
      businessId: businessId,
      type: 'payment',
      amount: amount,
      note: note,
      createdAt: createdAt,
    );
    await _db.updateCreditCustomerOwed(customerId: customerId, delta: -amount);

    if (_isOnline) {
      try {
        await _supabase.rpc('apply_credit_payment', params: {
          'p_payment_id': paymentTxId,
          'p_customer_id': customerId,
          'p_business_id': businessId,
          'p_amount': amount,
          'p_note': note,
          'p_created_at': createdAt,
        });
        return PaymentResult(
            paymentTxId: paymentTxId, settledCredits: const [], leftoverCredit: 0);
      } catch (e) {
        debugPrint('[Credit] apply_credit_payment failed, queuing: $e');
      }
    }

    await _ref.read(syncQueueServiceProvider).enqueue(
      operation: 'record_credit_payment',
      tableName: 'credit_transactions',
      recordId: paymentTxId,
      payload: {
        'payment_tx_id': paymentTxId,
        'customer_id': customerId,
        'business_id': businessId,
        'amount': amount,
        'note': note,
        'created_at': createdAt,
      },
    );
    return PaymentResult(
        paymentTxId: paymentTxId, settledCredits: const [], leftoverCredit: 0);
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
        isSettled: r['is_settled'] == true || r['is_settled'] == 1,
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