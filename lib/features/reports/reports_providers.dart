// features/reports/reports_providers.dart
// All models + Riverpod providers for the Reports feature.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/shift.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../features/auth/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DAILY REPORT MODELS
// ─────────────────────────────────────────────────────────────────────────────

class TopProduct {
  final String name;
  final int qty;
  final double revenue;
  const TopProduct(this.name, this.qty, this.revenue);
}

class HourlySale {
  final int hour;
  final double amount;
  const HourlySale(this.hour, this.amount);
}

class DailyReport {
  final double totalRevenue;
  final int totalOrders;
  final double avgOrderValue;
  final Map<String, double> revenueByPayment;
  final List<TopProduct> topProducts;
  final List<HourlySale> hourlySales;
  final int completedOrders;
  final int cancelledOrders;
  final bool isFromCache;
  final DateTime? cachedAt;

  const DailyReport({
    required this.totalRevenue,
    required this.totalOrders,
    required this.avgOrderValue,
    required this.revenueByPayment,
    required this.topProducts,
    required this.hourlySales,
    required this.completedOrders,
    required this.cancelledOrders,
    this.isFromCache = false,
    this.cachedAt,
  });

  static const empty = DailyReport(
    totalRevenue: 0,
    totalOrders: 0,
    avgOrderValue: 0,
    revenueByPayment: {},
    topProducts: [],
    hourlySales: [],
    completedOrders: 0,
    cancelledOrders: 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIFT REPORT MODELS
// ─────────────────────────────────────────────────────────────────────────────

class ShiftEntry {
  final CashierShift shift;
  final int orderCount;
  final int itemsSold;

  const ShiftEntry({
    required this.shift,
    required this.orderCount,
    required this.itemsSold,
  });

  Duration get duration {
    final end = shift.closedAt ?? DateTime.now();
    return end.difference(shift.openedAt);
  }

  double get avgOrderValue =>
      orderCount > 0 ? shift.totalSales / orderCount : 0;
}

class ShiftDaySummary {
  final double totalSales;
  final double cashSales;
  final double gcashSales;
  final double otherSales;
  final double creditGiven;
  final int totalOrders;
  final int totalItems;
  final int shiftCount;

  const ShiftDaySummary({
    required this.totalSales,
    required this.cashSales,
    required this.gcashSales,
    required this.otherSales,
    required this.creditGiven,
    required this.totalOrders,
    required this.totalItems,
    required this.shiftCount,
  });

  factory ShiftDaySummary.fromEntries(List<ShiftEntry> entries) =>
      ShiftDaySummary(
        totalSales: entries.fold(0, (s, e) => s + e.shift.totalSales),
        cashSales: entries.fold(0, (s, e) => s + e.shift.cashSales),
        gcashSales: entries.fold(0, (s, e) => s + e.shift.gcashSales),
        otherSales: entries.fold(0, (s, e) => s + e.shift.otherSales),
        creditGiven: entries.fold(0, (s, e) => s + e.shift.creditGiven),
        totalOrders: entries.fold(0, (s, e) => s + e.orderCount),
        totalItems: entries.fold(0, (s, e) => s + e.itemsSold),
        shiftCount: entries.length,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum ReportTab { daily, shifts }

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final reportTabProvider = StateProvider<ReportTab>((ref) => ReportTab.daily);

final dailyReportProvider =
    FutureProvider.family<DailyReport, DateTime>((ref, date) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) return DailyReport.empty;

  final businessId = profile!.businessId!;
  final isOnline = ref.read(isOnlineProvider);
  final local = ref.read(localDbServiceProvider);
  final dateKey =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  if (!isOnline) return _loadFromCache(local, businessId, dateKey);

  try {
    final client = ref.watch(supabaseClientProvider);
    final dayStart =
        DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59)
        .toUtc()
        .toIso8601String();

    final rows = await client
        .from('orders')
        .select('*, order_items(product_name, quantity, subtotal)')
        .eq('business_id', businessId)
        .gte('created_at', dayStart)
        .lte('created_at', dayEnd)
        .order('created_at');

    final report = _buildReport(rows as List, fromCache: false);

    await local.upsertReportDay(
      date: dateKey,
      businessId: businessId,
      totalSales: report.totalRevenue,
      orderCount: report.totalOrders,
      avgOrderValue: report.avgOrderValue,
      topProducts: report.topProducts
          .map((p) => {'name': p.name, 'qty': p.qty, 'revenue': p.revenue})
          .toList(),
    );

    return report;
  } catch (e) {
    return _loadFromCache(local, businessId, dateKey);
  }
});

final shiftReportProvider =
    FutureProvider.family<List<ShiftEntry>, DateTime>((ref, date) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile?.businessId == null) return [];
  final businessId = profile!.businessId!;

  final shiftService = ref.read(shiftServiceProvider);

  final dayStart = DateTime(date.year, date.month, date.day).toUtc();
  final dayEnd = dayStart.add(const Duration(days: 1));

  final isOnline = ref.read(isOnlineProvider);
  final local = ref.read(localDbServiceProvider);

  // ── Fetch shifts ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> shiftRows = [];

  if (isOnline) {
    try {
      final client = Supabase.instance.client;
      final raw = await client
          .from('cashier_shifts')
          .select()
          .eq('business_id', businessId)
          .gte('opened_at', dayStart.toIso8601String())
          .lt('opened_at', dayEnd.toIso8601String())
          .order('opened_at', ascending: true);
      shiftRows = List<Map<String, dynamic>>.from(raw as List);
    } catch (_) {
      shiftRows = await _localShiftRows(local, businessId, dayStart, dayEnd);
    }
  } else {
    shiftRows = await _localShiftRows(local, businessId, dayStart, dayEnd);
  }

  if (shiftRows.isEmpty) return [];

  // ── For each shift, count orders + items ────────────────────────────────────
  final entries = <ShiftEntry>[];

  for (final row in shiftRows) {
    final shift = shiftFromRow(row);
    final shiftEnd = (shift.closedAt ?? DateTime.now()).toUtc();
    int orderCount = 0;
    int itemsSold = 0;

    if (isOnline) {
      try {
        final client = Supabase.instance.client;
        final orders = await client
            .from('orders')
            .select('id')
            .eq('business_id', businessId)
            .eq('cashier_id', shift.staffId)
            .eq('status', 'completed')
            .gte('created_at', shift.openedAt.toUtc().toIso8601String())
            .lte('created_at', shiftEnd.toIso8601String());

        orderCount = (orders as List).length;

        if (orderCount > 0) {
          final ids = (orders).map((o) => o['id'] as String).toList();
          final items = await client
              .from('order_items')
              .select('quantity')
              .inFilter('order_id', ids);
          itemsSold =
              (items as List).fold(0, (s, i) => s + (i['quantity'] as int));
        }
      } catch (_) {
        final r = await _localOrderCounts(
          local, businessId, shift.staffId,
          shift.openedAt.toUtc(), shiftEnd,
        );
        orderCount = r.$1;
        itemsSold = r.$2;
      }
    } else {
      final r = await _localOrderCounts(
        local, businessId, shift.staffId,
        shift.openedAt.toUtc(), shiftEnd,
      );
      orderCount = r.$1;
      itemsSold = r.$2;
    }

    // ── BUG FIX: use liveShift (not raw shift) when shift is open ──────────
    final liveShift = shift.status == ShiftStatus.open
        ? await shiftService.withLiveTotals(shift)
        : shift;

    entries.add(ShiftEntry(
      shift: liveShift, // ← was `shift` before; now correctly uses live data
      orderCount: orderCount,
      itemsSold: itemsSold,
    ));
  }

  return entries;
});

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<DailyReport> _loadFromCache(
  LocalDbService local,
  String businessId,
  String dateKey,
) async {
  final cached =
      await local.getReports(businessId, fromDate: dateKey, toDate: dateKey);

  if (cached.isEmpty) {
    return DailyReport.empty.copyWith(isFromCache: true);
  }

  final row = cached.first;
  final syncedAt = row['synced_at'] != null
      ? DateTime.tryParse(row['synced_at'] as String)
      : null;
  final rawTopProducts =
      (row['top_products'] as List? ?? []).cast<Map<String, dynamic>>();

  return DailyReport(
    totalRevenue: (row['total_sales'] as num?)?.toDouble() ?? 0,
    totalOrders: (row['order_count'] as int?) ?? 0,
    avgOrderValue: (row['avg_order_value'] as num?)?.toDouble() ?? 0,
    revenueByPayment: const {},
    topProducts: rawTopProducts
        .map((p) => TopProduct(
              p['name'] as String,
              (p['qty'] as num).toInt(),
              (p['revenue'] as num).toDouble(),
            ))
        .toList(),
    hourlySales: List.generate(24, (h) => HourlySale(h, 0)),
    completedOrders: (row['order_count'] as int?) ?? 0,
    cancelledOrders: 0,
    isFromCache: true,
    cachedAt: syncedAt,
  );
}

DailyReport _buildReport(List orders, {required bool fromCache}) {
  double totalRevenue = 0;
  int completed = 0;
  int cancelled = 0;
  final Map<String, double> byPayment = {};
  final Map<String, TopProduct> productMap = {};
  final Map<int, double> hourMap = {};

  for (final o in orders) {
    final row = o as Map<String, dynamic>;
    final status = row['status'] as String? ?? '';

    if (status == 'cancelled') {
      cancelled++;
      continue;
    }

    final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
    final method = row['payment_method'] as String? ?? 'cash';
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
    final isPaid = status == 'completed' || row['paid_at'] != null;

    if (isPaid) {
      completed++;
      totalRevenue += amount;
      byPayment[method] = (byPayment[method] ?? 0) + amount;
    }

    if (createdAt != null) {
      final h = createdAt.toLocal().hour;
      if (isPaid) hourMap[h] = (hourMap[h] ?? 0) + amount;
    }

    final items = row['order_items'] as List? ?? [];
    for (final item in items) {
      final name = item['product_name'] as String? ?? 'Unknown';
      final qty = item['quantity'] as int? ?? 0;
      final sub = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
      final existing = productMap[name];
      productMap[name] = existing != null
          ? TopProduct(name, existing.qty + qty, existing.revenue + sub)
          : TopProduct(name, qty, sub);
    }
  }

  final topProducts = productMap.values.toList()
    ..sort((a, b) => b.qty.compareTo(a.qty));

  return DailyReport(
    totalRevenue: totalRevenue,
    totalOrders: orders.length,
    avgOrderValue: completed > 0 ? totalRevenue / completed : 0,
    revenueByPayment: byPayment,
    topProducts: topProducts.take(5).toList(),
    hourlySales: List.generate(24, (h) => HourlySale(h, hourMap[h] ?? 0)),
    completedOrders: completed,
    cancelledOrders: cancelled,
    isFromCache: fromCache,
  );
}

Future<List<Map<String, dynamic>>> _localShiftRows(
  LocalDbService local,
  String businessId,
  DateTime from,
  DateTime to,
) async {
  final db = await local.db;
  final rows = await db.query(
    'cashier_shifts',
    where: 'business_id = ? AND opened_at >= ? AND opened_at < ?',
    whereArgs: [businessId, from.toIso8601String(), to.toIso8601String()],
    orderBy: 'opened_at ASC',
  );
  return rows.cast<Map<String, dynamic>>();
}

Future<(int, int)> _localOrderCounts(
  LocalDbService local,
  String businessId,
  String staffId,
  DateTime from,
  DateTime to,
) async {
  final db = await local.db;
  final orders = await db.query(
    'orders',
    columns: ['id'],
    where:
        'business_id = ? AND cashier_id = ? AND status = ? AND created_at >= ? AND created_at <= ?',
    whereArgs: [
      businessId, staffId, 'completed',
      from.toIso8601String(), to.toIso8601String(),
    ],
  );
  if (orders.isEmpty) return (0, 0);
  final ids = orders.map((o) => "'${o['id']}'").join(',');
  final items = await db.rawQuery(
    'SELECT SUM(quantity) as total FROM order_items WHERE order_id IN ($ids)',
  );
  return (orders.length, (items.first['total'] as num?)?.toInt() ?? 0);
}

/// Public so shift widgets can call it directly if needed.
CashierShift shiftFromRow(Map<String, dynamic> r) => CashierShift(
      id: r['id'] as String,
      businessId: r['business_id'] as String,
      staffId: r['staff_id'] as String,
      staffName: r['staff_name'] as String,
      openingCash: (r['opening_cash'] as num).toDouble(),
      openedAt: DateTime.parse(r['opened_at'] as String).toLocal(),
      status: r['status'] == 'open' ? ShiftStatus.open : ShiftStatus.closed,
      closedAt: r['closed_at'] != null
          ? DateTime.parse(r['closed_at'] as String).toLocal()
          : null,
      actualCashCount: (r['actual_cash_count'] as num?)?.toDouble(),
      notes: r['notes'] as String?,
      totalSales: (r['total_sales'] as num? ?? 0).toDouble(),
      cashSales: (r['cash_sales'] as num? ?? 0).toDouble(),
      gcashSales: (r['gcash_sales'] as num? ?? 0).toDouble(),
      otherSales: (r['other_sales'] as num? ?? 0).toDouble(),
      creditGiven: (r['credit_given'] as num? ?? 0).toDouble(),
      expenses: (r['expenses'] as num? ?? 0).toDouble(),
    );

// ─────────────────────────────────────────────────────────────────────────────
// copyWith extension for DailyReport (needed for cache helper)
// ─────────────────────────────────────────────────────────────────────────────

extension DailyReportCopyWith on DailyReport {
  DailyReport copyWith({
    double? totalRevenue,
    int? totalOrders,
    double? avgOrderValue,
    Map<String, double>? revenueByPayment,
    List<TopProduct>? topProducts,
    List<HourlySale>? hourlySales,
    int? completedOrders,
    int? cancelledOrders,
    bool? isFromCache,
    DateTime? cachedAt,
  }) =>
      DailyReport(
        totalRevenue: totalRevenue ?? this.totalRevenue,
        totalOrders: totalOrders ?? this.totalOrders,
        avgOrderValue: avgOrderValue ?? this.avgOrderValue,
        revenueByPayment: revenueByPayment ?? this.revenueByPayment,
        topProducts: topProducts ?? this.topProducts,
        hourlySales: hourlySales ?? this.hourlySales,
        completedOrders: completedOrders ?? this.completedOrders,
        cancelledOrders: cancelledOrders ?? this.cancelledOrders,
        isFromCache: isFromCache ?? this.isFromCache,
        cachedAt: cachedAt ?? this.cachedAt,
      );
}