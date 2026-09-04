// lib/core/services/shift_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // ── Device ID ──────────────────────────────────────────────────────────────

  static String? _cachedDeviceId;

  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
    }
    _cachedDeviceId = id;
    return id;
  }

  // ── Open Shift ─────────────────────────────────────────────────────────────

  Future<CashierShift> openShift({
    required String businessId,
    required String staffId,
    required String staffName,
    required double openingCash,
  }) async {
    final deviceId = await _getDeviceId();
    final existing = await getOpenShift(
        businessId: businessId, staffId: staffId, deviceId: deviceId);
    if (existing != null) return existing;

    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();

    final payload = {
      'id': id,
      'business_id': businessId,
      'staff_id': staffId,
      'staff_name': staffName,
      'device_id': deviceId,
      'opening_cash': openingCash,
      'opened_at': now.toIso8601String(),
      'status': 'open',
      'total_sales': 0.0,
      'cash_sales': 0.0,
      'gcash_sales': 0.0,
      'other_sales': 0.0,
      'credit_given': 0.0,
      'credits_paid': 0.0,
      'expenses': 0.0,
    };

    try {
      await _supabase.from('cashier_shifts').insert(payload);
    } catch (_) {}

    final d = await _db.db;
    await d.insert('cashier_shifts', payload,
        conflictAlgorithm: ConflictAlgorithm.replace);

    final shift = CashierShift(
      id: id,
      businessId: businessId,
      staffId: staffId,
      staffName: staffName,
      openingCash: openingCash,
      openedAt: now,
      status: ShiftStatus.open,
    );

    return shift;
  }

  // ── Get Open Shift ─────────────────────────────────────────────────────────

  Future<CashierShift?> getOpenShift({
    required String businessId,
    required String staffId,
    String? deviceId,
  }) async {
    final resolvedDeviceId = deviceId ?? await _getDeviceId();

    try {
      var query = _supabase
          .from('cashier_shifts')
          .select()
          .eq('business_id', businessId)
          .eq('staff_id', staffId)
          .eq('status', 'open');

      // Search any device — so Device B joins Device A's open shift
      // instead of prompting to open a new one.
      final rows = await query
          .order('opened_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final shift = _shiftFromMap(rows.first);
        final d = await _db.db;
        await d.insert('cashier_shifts', _shiftToRow(shift),
            conflictAlgorithm: ConflictAlgorithm.replace);
        return shift;
      }
      return null;
      
    } catch (_) {}

    // Offline fallback
    final d = await _db.db;
    final rows = await d.query(
      'cashier_shifts',
      where:
          'business_id = ? AND staff_id = ? AND status = ? AND device_id = ?',
      whereArgs: [businessId, staffId, 'open', resolvedDeviceId],
      orderBy: 'opened_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      final fallback = await d.query(
        'cashier_shifts',
        where: 'business_id = ? AND staff_id = ? AND status = ?',
        whereArgs: [businessId, staffId, 'open'],
        orderBy: 'opened_at DESC',
        limit: 1,
      );
      if (fallback.isEmpty) return null;
      return _shiftFromMap(fallback.first);
    }
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
      to: DateTime.now().toUtc(),
    );

    final now = DateTime.now().toUtc();
    // Read the running expense total from local DB
    final d2 = await _db.db;
    final expRows = await d2.query(
      'cashier_shifts',
      columns: ['expenses'],
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    final expenses =
        (expRows.firstOrNull?['expenses'] as num? ?? 0).toDouble();

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
      'credits_paid': summary['credits_paid'],
      'expenses': expenses,
    };

    try {
      await _supabase
          .from('cashier_shifts')
          .update(updates)
          .eq('id', shiftId);
      debugPrint('[ShiftClose] Supabase update OK for $shiftId');
    } catch (e) {
      debugPrint('[ShiftClose] Supabase update FAILED: $e');
    }

    final d = await _db.db;
    final rowsAffected = await d.update('cashier_shifts', updates,
        where: 'id = ?', whereArgs: [shiftId]);
    debugPrint('[ShiftClose] SQLite rows affected: $rowsAffected for $shiftId');


    final closed = shift.copyWith(
      status: ShiftStatus.closed,
      closedAt: now,
      actualCashCount: actualCashCount,
      notes: notes,
      totalSales: summary['total_sales']!,
      cashSales: summary['cash_sales']!,
      gcashSales: summary['gcash_sales']!,
      otherSales: summary['other_sales']!,
      creditGiven: summary['credit_given']!,
      creditsPaid: summary['credits_paid']!,
      expenses: expenses,
    );

    debugPrint('[ShiftClose] Closed shift: ${closed.id}');

    return closed;
  }

  // ── Live totals preview ────────────────────────────────────────────────────

  Future<CashierShift> withLiveTotals(CashierShift shift) async {
    final summary = await _computeShiftSummary(
      businessId: shift.businessId,
      staffId: shift.staffId,
      from: shift.openedAt,
      to: DateTime.now().toUtc(),
    );
    return shift.copyWith(
      totalSales: summary['total_sales'],
      cashSales: summary['cash_sales'],
      gcashSales: summary['gcash_sales'],
      otherSales: summary['other_sales'],
      creditGiven: summary['credit_given'],
      creditsPaid: summary['credits_paid'],
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
    double creditsPaid = 0;

    final splitOrderIds = <String>[];

    void tally(Map<String, dynamic> o) {
      final status = o['status'] as String? ?? '';
      final paidAt = o['paid_at'];
      final isPaid = status == 'completed' || paidAt != null;
      if (!isPaid) return;

      final amount = (o['total_amount'] as num).toDouble();
      final isSplit = (o['is_split_payment'] as bool?) ?? false;

      if (isSplit) {
        // Defer — real per-method breakdown comes from order_payments,
        // fetched in one batch below to avoid N+1 queries.
        splitOrderIds.add(o['id'] as String);
        totalSales += amount;
        return;
      }

      final method = o['payment_method'] as String? ?? '';
      totalSales += amount;

      switch (method) {
        case 'cash':
          cashSales += amount;
        case 'gcash':
        case 'maya':
        case 'e_wallet':
          gcashSales += amount;
        case 'credit':
          creditGiven += amount;
          totalSales -= amount; // credit sales are not collected cash
        default:
          otherSales += amount;
      }
    }

    Future<void> tallySplitOrders() async {
      if (splitOrderIds.isEmpty) return;
      try {
        final legs = await _supabase
            .from('order_payments')
            .select('order_id, method, amount')
            .inFilter('order_id', splitOrderIds);
        for (final leg in legs as List) {
          final amount = (leg['amount'] as num).toDouble();
          switch (leg['method'] as String) {
            case 'cash':
              cashSales += amount;
            case 'gcash':
            case 'maya':
              gcashSales += amount;
            case 'credit':
              creditGiven += amount; // shouldn't normally occur in a split leg
            default:
              otherSales += amount;
          }
        }
      } catch (_) {
        // Offline fallback — same table exists locally.
        final d = await _db.db;
        final placeholders = List.filled(splitOrderIds.length, '?').join(',');
        final legs = await d.rawQuery(
          'SELECT method, amount FROM order_payments WHERE order_id IN ($placeholders)',
          splitOrderIds,
        );
        for (final leg in legs) {
          final amount = (leg['amount'] as num).toDouble();
          switch (leg['method'] as String) {
            case 'cash':
              cashSales += amount;
            case 'gcash':
            case 'maya':
              gcashSales += amount;
            case 'credit':
              creditGiven += amount;
            default:
              otherSales += amount;
          }
        }
      }
    }

    try {
      // ── Tally paid orders ──────────────────────────────────────────────────
      // Fetch orders assigned to this staff member
      final assignedOrders = await _supabase
          .from('orders')
          .select('id, total_amount, payment_method, status, paid_at, is_split_payment')
          .eq('business_id', businessId)
          .eq('cashier_id', staffId)
          .gte('created_at', from.toUtc().toIso8601String())
          .lte('created_at', to.toUtc().toIso8601String());

      for (final o in assignedOrders) {
        tally(o);
      }

      // Also include orders with no cashier_id (owner-placed orders on older
      // accounts that were created before the staff row existed)
      final nullCashierOrders = await _supabase
          .from('orders')
          .select('id, total_amount, payment_method, status, paid_at, is_split_payment')
          .eq('business_id', businessId)
          .isFilter('cashier_id', null)
          .gte('created_at', from.toUtc().toIso8601String())
          .lte('created_at', to.toUtc().toIso8601String());

      for (final o in nullCashierOrders) {
        tally(o);
      }

      // ── Tally credit given ─────────────────────────────────────────────────
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

      // ── Tally credits paid (payments collected on existing utang) ──────────
      try {
        final payments = await _supabase
            .from('credit_transactions')
            .select('amount')
            .eq('business_id', businessId)
            .eq('type', 'payment')
            .gte('created_at', from.toUtc().toIso8601String())
            .lte('created_at', to.toUtc().toIso8601String());

        for (final p in payments) {
          creditsPaid += (p['amount'] as num).toDouble();
        }
      } catch (_) {}

      await tallySplitOrders();
    } catch (_) {
      // ── Full offline fallback ──────────────────────────────────────────────
      final d = await _db.db;

      final rows = await d.rawQuery('''
        SELECT total_amount, payment_method, status, paid_at FROM orders
        WHERE business_id = ?
          AND (cashier_id = ? OR cashier_id IS NULL)
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

      // Credit given — offline
      try {
        final creditRows = await d.rawQuery('''
          SELECT amount FROM credit_transactions
          WHERE type = 'credit'
            AND created_at >= ? AND created_at <= ?
        ''', [
          from.toUtc().toIso8601String(),
          to.toUtc().toIso8601String(),
        ]);
        for (final c in creditRows) {
          creditGiven += (c['amount'] as num).toDouble();
        }
      } catch (_) {}

      // Credits paid — offline
      try {
        final paymentRows = await d.rawQuery('''
          SELECT amount FROM credit_transactions
          WHERE type = 'payment'
            AND created_at >= ? AND created_at <= ?
        ''', [
          from.toUtc().toIso8601String(),
          to.toUtc().toIso8601String(),
        ]);
        for (final p in paymentRows) {
          creditsPaid += (p['amount'] as num).toDouble();
        }
      } catch (_) {}
    }

    return {
      'total_sales': totalSales,
      'cash_sales': cashSales,
      'gcash_sales': gcashSales,
      'other_sales': otherSales,
      'credit_given': creditGiven,
      'credits_paid': creditsPaid,
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

  // ── Log expense ────────────────────────────────────────────────────────────

  Future<void> logExpense({
    required String shiftId,
    required String businessId,
    required double amount,
    required String description,
  }) async {
    // 1. Update local SQLite first so UI reflects change immediately
    final d = await _db.db;
    await d.rawUpdate(
      'UPDATE cashier_shifts SET expenses = expenses + ? WHERE id = ?',
      [amount, shiftId],
    );

    // 2. Sync to Supabase
    try {
      await _supabase.rpc('increment_shift_expenses', params: {
        'p_shift_id': shiftId,
        'p_amount': amount,
      });
    } catch (_) {
      // Non-fatal — local value is correct, Supabase will be updated
      // at shift close when the full summary is written.
    }
  }

  Future<double> getExpenses(String shiftId) async {
    final d = await _db.db;
    final rows = await d.query(
      'cashier_shifts',
      columns: ['expenses'],
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['expenses'] as num? ?? 0).toDouble();
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
        creditsPaid: (r['credits_paid'] as num? ?? 0).toDouble(),
        expenses: (r['expenses'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> _shiftToRow(CashierShift s) => {
        'id': s.id,
        'business_id': s.businessId,
        'staff_id': s.staffId,
        'staff_name': s.staffName,
        'opening_cash': s.openingCash,
        'opened_at': s.openedAt.toUtc().toIso8601String(),
        'status': s.status == ShiftStatus.open ? 'open' : 'closed',
        'closed_at': s.closedAt?.toUtc().toIso8601String(),
        'actual_cash_count': s.actualCashCount,
        'notes': s.notes,
        'total_sales': s.totalSales,
        'cash_sales': s.cashSales,
        'gcash_sales': s.gcashSales,
        'other_sales': s.otherSales,
        'credit_given': s.creditGiven,
        'credits_paid': s.creditsPaid,
        'expenses': s.expenses,
      };
}