// lib/core/services/shift_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/shift.dart';
import 'local_db_service.dart';

final shiftServiceProvider = Provider<ShiftService>((ref) {
  return ShiftService(
    ref.watch(localDbServiceProvider),
    Supabase.instance.client,
  );
});

class ShiftService {
  final LocalDbService _db;
  final SupabaseClient _supabase;

  const ShiftService(this._db, this._supabase);

  // ── Open Shift ─────────────────────────────────────────────────────────────

  Future<CashierShift> openShift({
    required String businessId,
    required String staffId,
    required String staffName,
    required double openingCash,
  }) async {
    // Guard: only one open shift per staff at a time
    final existing = await getOpenShift(businessId: businessId, staffId: staffId);
    if (existing != null) return existing;

    final id = const Uuid().v4();
    final now = DateTime.now();

    final payload = {
      'id': id,
      'business_id': businessId,
      'staff_id': staffId,
      'staff_name': staffName,
      'opening_cash': openingCash,
      'opened_at': now.toIso8601String(),
      'status': 'open',
      'total_sales': 0.0,
      'cash_sales': 0.0,
      'gcash_sales': 0.0,
      'other_sales': 0.0,
      'credit_given': 0.0,
      'expenses': 0.0,
    };

    // 1. Supabase
    try {
      await _supabase.from('cashier_shifts').insert(payload);
    } catch (_) {
      // offline — will sync later
    }

    // 2. SQLite
    final d = await _db.db;
    await d.insert('cashier_shifts', payload,
        conflictAlgorithm: ConflictAlgorithm.replace);

    return CashierShift(
      id: id,
      businessId: businessId,
      staffId: staffId,
      staffName: staffName,
      openingCash: openingCash,
      openedAt: now,
      status: ShiftStatus.open,
    );
  }

  // ── Get Open Shift ─────────────────────────────────────────────────────────

  Future<CashierShift?> getOpenShift({
    required String businessId,
    required String staffId,
  }) async {
    // Try Supabase first
    try {
      final rows = await _supabase
          .from('cashier_shifts')
          .select()
          .eq('business_id', businessId)
          .eq('staff_id', staffId)
          .eq('status', 'open')
          .order('opened_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final shift = _shiftFromMap(rows.first);
        // Keep local in sync
        final d = await _db.db;
        await d.insert('cashier_shifts', _shiftToRow(shift),
            conflictAlgorithm: ConflictAlgorithm.replace);
        return shift;
      }
    } catch (_) {
      // Offline fallback
    }

    // SQLite fallback
    final d = await _db.db;
    final rows = await d.query(
      'cashier_shifts',
      where: 'business_id = ? AND staff_id = ? AND status = ?',
      whereArgs: [businessId, staffId, 'open'],
      orderBy: 'opened_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _shiftFromMap(rows.first);
  }

  // ── Close Shift ────────────────────────────────────────────────────────────

  Future<CashierShift> closeShift({
    required String shiftId,
    required double actualCashCount,
    String? notes,
  }) async {
    // 1. Compute sales totals from orders during this shift
    final shift = await _getShiftById(shiftId);
    if (shift == null) throw Exception('Shift not found');

    final summary = await _computeShiftSummary(
      businessId: shift.businessId,
      staffId: shift.staffId,
      from: shift.openedAt,
      to: DateTime.now(),
    );

    final now = DateTime.now();
    final updates = {
      'status': 'closed',
      'closed_at': now.toIso8601String(),
      'actual_cash_count': actualCashCount,
      'notes': notes,
      'total_sales': summary['total_sales'],
      'cash_sales': summary['cash_sales'],
      'gcash_sales': summary['gcash_sales'],
      'other_sales': summary['other_sales'],
      'credit_given': summary['credit_given'],
    };

    // 2. Supabase update
    try {
      await _supabase
          .from('cashier_shifts')
          .update(updates)
          .eq('id', shiftId);
    } catch (_) {
      // offline
    }

    // 3. SQLite update
    final d = await _db.db;
    await d.update('cashier_shifts', updates,
        where: 'id = ?', whereArgs: [shiftId]);

    return shift.copyWith(
      status: ShiftStatus.closed,
      closedAt: now,
      actualCashCount: actualCashCount,
      notes: notes,
      totalSales: summary['total_sales']!,
      cashSales: summary['cash_sales']!,
      gcashSales: summary['gcash_sales']!,
      otherSales: summary['other_sales']!,
      creditGiven: summary['credit_given']!,
    );
  }

  // ── Compute shift totals from orders ───────────────────────────────────────

  Future<Map<String, double>> _computeShiftSummary({
    required String businessId,
    required String staffId,
    required DateTime from,
    required DateTime to,
  }) async {
    double totalSales = 0;
    double cashSales = 0;
    double gcashSales = 0;
    double otherSales = 0;
    double creditGiven = 0;

    try {
      // Orders paid during this shift window by this cashier
      final orders = await _supabase
          .from('orders')
          .select('total_amount, payment_method')
          .eq('business_id', businessId)
          .eq('cashier_id', staffId)
          .eq('status', 'paid')
          .gte('paid_at', from.toIso8601String())
          .lte('paid_at', to.toIso8601String());

      for (final o in orders) {
        final amount = (o['total_amount'] as num).toDouble();
        final method = o['payment_method'] as String? ?? '';
        totalSales += amount;
        if (method == 'cash') {
          cashSales += amount;
        } else if (method == 'gcash' || method == 'e_wallet') {
          gcashSales += amount;
        } else if (method == 'credit') {
          creditGiven += amount;
        } else {
          otherSales += amount;
        }
      }

      // Also count utang (credit payment method orders)
      // credit_given is already captured above via payment_method == 'credit'
    } catch (_) {
      // Offline: compute from local SQLite orders
      final d = await _db.db;
      final rows = await d.rawQuery('''
        SELECT total_amount, payment_method FROM orders
        WHERE business_id = ? AND cashier_id = ? AND status = 'paid'
          AND paid_at >= ? AND paid_at <= ?
      ''', [
        businessId,
        staffId,
        from.toIso8601String(),
        to.toIso8601String(),
      ]);

      for (final o in rows) {
        final amount = (o['total_amount'] as num).toDouble();
        final method = o['payment_method'] as String? ?? '';
        totalSales += amount;
        if (method == 'cash') {
          cashSales += amount;
        } else if (method == 'gcash' || method == 'e_wallet') {
          gcashSales += amount;
        } else if (method == 'credit') {
          creditGiven += amount;
        } else {
          otherSales += amount;
        }
      }
    }

    return {
      'total_sales': totalSales,
      'cash_sales': cashSales,
      'gcash_sales': gcashSales,
      'other_sales': otherSales,
      'credit_given': creditGiven,
    };
  }

  Future<CashierShift?> _getShiftById(String shiftId) async {
    try {
      final rows = await _supabase
          .from('cashier_shifts')
          .select()
          .eq('id', shiftId)
          .limit(1);
      if (rows.isNotEmpty) return _shiftFromMap(rows.first);
    } catch (_) {}
    final d = await _db.db;
    final rows = await d.query('cashier_shifts',
        where: 'id = ?', whereArgs: [shiftId], limit: 1);
    if (rows.isEmpty) return null;
    return _shiftFromMap(rows.first);
  }

  // ── Shift history ──────────────────────────────────────────────────────────

  Future<List<CashierShift>> getShiftHistory({
    required String businessId,
    required String staffId,
    int limit = 20,
  }) async {
    try {
      final rows = await _supabase
          .from('cashier_shifts')
          .select()
          .eq('business_id', businessId)
          .eq('staff_id', staffId)
          .order('opened_at', ascending: false)
          .limit(limit);
      return rows.map(_shiftFromMap).toList();
    } catch (_) {
      final d = await _db.db;
      final rows = await d.query(
        'cashier_shifts',
        where: 'business_id = ? AND staff_id = ?',
        whereArgs: [businessId, staffId],
        orderBy: 'opened_at DESC',
        limit: limit,
      );
      return rows.map(_shiftFromMap).toList();
    }
  }

  // ── Mappers ────────────────────────────────────────────────────────────────

  CashierShift _shiftFromMap(Map<String, dynamic> r) => CashierShift(
        id: r['id'] as String,
        businessId: r['business_id'] as String,
        staffId: r['staff_id'] as String,
        staffName: r['staff_name'] as String,
        openingCash: (r['opening_cash'] as num).toDouble(),
        openedAt: DateTime.parse(r['opened_at'] as String),
        status: r['status'] == 'open' ? ShiftStatus.open : ShiftStatus.closed,
        closedAt: r['closed_at'] != null
            ? DateTime.parse(r['closed_at'] as String)
            : null,
        actualCashCount: r['actual_cash_count'] != null
            ? (r['actual_cash_count'] as num).toDouble()
            : null,
        notes: r['notes'] as String?,
        totalSales: (r['total_sales'] as num? ?? 0).toDouble(),
        cashSales: (r['cash_sales'] as num? ?? 0).toDouble(),
        gcashSales: (r['gcash_sales'] as num? ?? 0).toDouble(),
        otherSales: (r['other_sales'] as num? ?? 0).toDouble(),
        creditGiven: (r['credit_given'] as num? ?? 0).toDouble(),
        expenses: (r['expenses'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> _shiftToRow(CashierShift s) => {
        'id': s.id,
        'business_id': s.businessId,
        'staff_id': s.staffId,
        'staff_name': s.staffName,
        'opening_cash': s.openingCash,
        'opened_at': s.openedAt.toIso8601String(),
        'status': s.status == ShiftStatus.open ? 'open' : 'closed',
        'closed_at': s.closedAt?.toIso8601String(),
        'actual_cash_count': s.actualCashCount,
        'notes': s.notes,
        'total_sales': s.totalSales,
        'cash_sales': s.cashSales,
        'gcash_sales': s.gcashSales,
        'other_sales': s.otherSales,
        'credit_given': s.creditGiven,
        'expenses': s.expenses,
      };
}