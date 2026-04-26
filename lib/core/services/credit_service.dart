// lib/core/services/credit_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/credit.dart';
import 'local_db_service.dart';

final creditServiceProvider = Provider<CreditService>((ref) {
  return CreditService(
    ref.watch(localDbServiceProvider),
    Supabase.instance.client,
  );
});

class CreditService {
  final LocalDbService _db;
  final SupabaseClient _supabase;

  const CreditService(this._db, this._supabase);

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
          'amount_remaining': amount, // starts fully unpaid
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
        'type': 'credit',
        'amount': amount,
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

  /// Record payment — FIFO: applies against oldest unpaid utang first
  Future<PaymentResult> recordPayment({
    required String customerId,
    required String businessId,
    required double amount,
    String? note,
  }) async {
    // 1. Fetch all unsettled credit transactions, oldest first
    final unsettled = await _supabase
        .from('credit_transactions')
        .select()
        .eq('customer_id', customerId)
        .eq('type', 'credit')
        .eq('is_settled', false)
        .order('created_at', ascending: true); // FIFO

    // 2. Insert the payment transaction
    final paymentRow = await _supabase
        .from('credit_transactions')
        .insert({
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

    final paymentTxId = paymentRow['id'] as String;

    // 3. Apply FIFO settlement
    double remaining = amount;
    final settlements = <Map<String, dynamic>>[];
    final creditUpdates = <Map<String, dynamic>>[];

    for (final row in unsettled) {
      if (remaining <= 0) break;

      final creditTxId = row['id'] as String;
      final amountRemaining = (row['amount_remaining'] as num).toDouble();
      final applied = remaining >= amountRemaining ? amountRemaining : remaining;
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
        'settled_at': newRemaining == 0 ? DateTime.now().toIso8601String() : null,
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

    // 6. Update customer total_owed
    await _supabase.rpc('decrement_credit_owed', params: {
      'p_customer_id': customerId,
      'p_amount': amount,
    });

    // 7. Mirror payment to SQLite
    final d = await _db.db;
    await d.transaction((txn) async {
      await txn.insert('credit_transactions', {
        'id': paymentTxId,
        'customer_id': customerId,
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
      leftoverCredit: remaining, // >0 means overpayment (rare)
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
        businessId: r['business_id'] as String,
        type: r['type'] == 'credit' ? CreditTxType.credit : CreditTxType.payment,
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
  final List<String> settledCredits; // IDs of utang fully paid off
  final double leftoverCredit;       // overpayment amount (usually 0)

  const PaymentResult({
    required this.paymentTxId,
    required this.settledCredits,
    required this.leftoverCredit,
  });
}