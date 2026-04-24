// lib/core/services/credit_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/credit.dart';
import 'local_db_service.dart';

final creditServiceProvider = Provider<CreditService>((ref) {
  return CreditService(ref.watch(localDbServiceProvider));
});

class CreditService {
  final LocalDbService _db;
  const CreditService(this._db);

  // ── Customers ─────────────────────────────────────────────────────────────

  Future<List<CreditCustomer>> getCustomers(String businessId) async {
    final d = await _db.db;
    final rows = await d.query(
      'credit_customers',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(_customerFromRow).toList();
  }

  Future<CreditCustomer?> findCustomerByPhone(
      String businessId, String phone) async {
    final d = await _db.db;
    final rows = await d.query(
      'credit_customers',
      where: 'business_id = ? AND phone = ?',
      whereArgs: [businessId, phone],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _customerFromRow(rows.first);
  }

  Future<CreditCustomer> createCustomer({
    required String businessId,
    required String name,
    required String phone,
  }) async {
    final d = await _db.db;
    final now = DateTime.now();
    final id = const Uuid().v4();
    final customer = CreditCustomer(
      id: id,
      businessId: businessId,
      name: name,
      phone: phone,
      totalOwed: 0,
      createdAt: now,
      updatedAt: now,
    );
    await d.insert('credit_customers', {
      'id': id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'total_owed': 0.0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return customer;
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  Future<List<CreditTransaction>> getTransactions(String customerId) async {
    final d = await _db.db;
    final rows = await d.query(
      'credit_transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_txFromRow).toList();
  }

  /// Add utang — called at checkout
  Future<void> addCredit({
    required String customerId,
    required double amount,
    String? note,
    String? orderId,
  }) async {
    final d = await _db.db;
    final now = DateTime.now();
    await d.transaction((txn) async {
      await txn.insert('credit_transactions', {
        'id': const Uuid().v4(),
        'customer_id': customerId,
        'type': 'credit',
        'amount': amount,
        'note': note,
        'order_id': orderId,
        'created_at': now.toIso8601String(),
      });
      await txn.rawUpdate(
        'UPDATE credit_customers SET total_owed = total_owed + ?, updated_at = ? WHERE id = ?',
        [amount, now.toIso8601String(), customerId],
      );
    });
  }

  /// Record payment — partial or full
  Future<void> recordPayment({
    required String customerId,
    required double amount,
    String? note,
  }) async {
    final d = await _db.db;
    final now = DateTime.now();
    await d.transaction((txn) async {
      await txn.insert('credit_transactions', {
        'id': const Uuid().v4(),
        'customer_id': customerId,
        'type': 'payment',
        'amount': amount,
        'note': note,
        'order_id': null,
        'created_at': now.toIso8601String(),
      });
      await txn.rawUpdate(
        'UPDATE credit_customers SET total_owed = MAX(0, total_owed - ?), updated_at = ? WHERE id = ?',
        [amount, now.toIso8601String(), customerId],
      );
    });
  }

  // ── Mappers ───────────────────────────────────────────────────────────────

  CreditCustomer _customerFromRow(Map<String, dynamic> r) => CreditCustomer(
        id: r['id'] as String,
        businessId: r['business_id'] as String,
        name: r['name'] as String,
        phone: r['phone'] as String,
        totalOwed: (r['total_owed'] as num).toDouble(),
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  CreditTransaction _txFromRow(Map<String, dynamic> r) => CreditTransaction(
        id: r['id'] as String,
        customerId: r['customer_id'] as String,
        type: r['type'] == 'credit' ? CreditTxType.credit : CreditTxType.payment,
        amount: (r['amount'] as num).toDouble(),
        note: r['note'] as String?,
        orderId: r['order_id'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}