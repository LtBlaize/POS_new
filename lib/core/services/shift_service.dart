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
    final existing =
        await getOpenShift(businessId: businessId, staffId: staffId);
    if (existing != null) return existing;

    final id = const Uuid().v4();
    // FIX: always use UTC so timestamps match Supabase-stored order created_at
    final now = DateTime.now().toUtc();

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

    try {
      await _supabase.from('cashier_shifts').insert(payload);
    } catch (_) {}

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
        final d = await _db.db;
        await d.insert('cashier_shifts', _shiftToRow(shift),
            conflictAlgorithm: ConflictAlgorithm.replace);
        return shift;
      }
    } catch (_) {}

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
    final shift = await _getShiftById(shiftId);
    if (shift == null) throw Exception('Shift not found');

    final summary = await _computeShiftSummary(
      businessId: shift.businessId,
      staffId: shift.staffId,
      from: shift.openedAt,
      to: DateTime.now().toUtc(),   // ← FIX: UTC
    );

    final now = DateTime.now().toUtc();   // ← FIX: UTC
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

    try {
      await _supabase
          .from('cashier_shifts')
          .update(updates)
          .eq('id', shiftId);
    } catch (_) {}

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

  // ── Live totals preview (used by currentShiftProvider) ────────────────────

  Future<CashierShift> withLiveTotals(CashierShift shift) async {
    final summary = await _computeShiftSummary(
      businessId: shift.businessId,
      staffId: shift.staffId,
      from: shift.openedAt,
      to: DateTime.now().toUtc(),   // ← FIX: UTC
    );
    return shift.copyWith(
      totalSales: summary['total_sales'],
      cashSales: summary['cash_sales'],
      gcashSales: summary['gcash_sales'],
      otherSales: summary['other_sales'],
      creditGiven: summary['credit_given'],
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

    void tally(Map<String, dynamic> o) {
      final status = o['status'] as String? ?? '';
      final paidAt = o['paid_at'];
      final isPaid = status == 'completed' || paidAt != null;
      if (!isPaid) return;

      final amount = (o['total_amount'] as num).toDouble();
      final method = o['payment_method'] as String? ?? '';

      totalSales += amount;

      switch (method) {
        case 'cash':
          cashSales += amount;
        case 'gcash':
        case 'maya':
        case 'e_wallet':
          gcashSales += amount;
        default:
          otherSales += amount;
      }
    }

    try {
      // FIX: use toUtc() on from/to so the ISO string has 'Z' suffix,
      // matching how Supabase stores order created_at timestamps.
      final orders = await _supabase
          .from('orders')
          .select('total_amount, payment_method, status, paid_at')
          .eq('business_id', businessId)
          .eq('cashier_id', staffId)
          .gte('created_at', from.toUtc().toIso8601String())
          .lte('created_at', to.toUtc().toIso8601String());

      for (final o in orders) {
        tally(o);
      }

      try {
        final credits = await _supabase
            .from('credit_transactions')
            .select('amount')
            .eq('business_id', businessId)
            .eq('type', 'credit')
            .gte('created_at', from.toUtc().toIso8601String())
            .lte('created_at', to.toUtc().toIso8601String());

        for (final c in credits) {
          creditGiven += (c['amount'] as num).toDouble();
        }
      } catch (_) {}
    } catch (_) {
      final d = await _db.db;
      final rows = await d.rawQuery('''
        SELECT total_amount, payment_method, status, paid_at FROM orders
        WHERE business_id = ? AND cashier_id = ?
          AND created_at >= ? AND created_at <= ?
      ''', [
        businessId,
        staffId,
        from.toUtc().toIso8601String(),
        to.toUtc().toIso8601String(),
      ]);

      for (final o in rows) {
        tally(o);
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
        // FIX: parse as UTC so duration calculation is correct
        openedAt: DateTime.parse(r['opened_at'] as String).toLocal(),
        status:
            r['status'] == 'open' ? ShiftStatus.open : ShiftStatus.closed,
        closedAt: r['closed_at'] != null
            ? DateTime.parse(r['closed_at'] as String).toLocal()
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
        'opened_at': s.openedAt.toUtc().toIso8601String(),  // ← FIX: UTC
        'status': s.status == ShiftStatus.open ? 'open' : 'closed',
        'closed_at': s.closedAt?.toUtc().toIso8601String(), // ← FIX: UTC
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