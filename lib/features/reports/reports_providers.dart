// features/reports/reports_providers.dart
// All models + Riverpod providers for the Reports feature.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/shift.dart';
import '../../core/services/shift_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/providers/app_context_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DAILY REPORT MODELS
// ─────────────────────────────────────────────────────────────────────────────

class TopProduct {
  final String name;
  final int qty;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double marginPct;
  final String category;

  const TopProduct(
    this.name,
    this.qty,
    this.revenue, {
    this.cogs = 0,
    this.grossProfit = 0,
    this.marginPct = 0,
    this.category = '',
  });
}

class HourlySale {
  final int hour;
  final double amount;
  const HourlySale(this.hour, this.amount);
}

class HeatmapCell {
  final int weekday; // 1=Mon … 7=Sun
  final int hour;    // 0–23
  final double amount;
  final int orderCount;
  const HeatmapCell({
    required this.weekday,
    required this.hour,
    required this.amount,
    required this.orderCount,
  });
}

class WeeklyHeatmap {
  final List<HeatmapCell> cells; // 7 × 24 = 168 entries
  final double maxAmount;
  const WeeklyHeatmap({required this.cells, required this.maxAmount});
  static const empty = WeeklyHeatmap(cells: [], maxAmount: 0);
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
  final double totalCogs;
  final double grossProfit;
  final double totalTaxCollected;
  final double totalDiscount;
  final Map<String, double> discountByStaff;
  final bool isFromCache;
  final DateTime? cachedAt;

  double get marginPct =>
      totalRevenue > 0 ? (grossProfit / totalRevenue * 100) : 0;

  const DailyReport({
    required this.totalRevenue,
    required this.totalOrders,
    required this.avgOrderValue,
    required this.revenueByPayment,
    required this.topProducts,
    required this.hourlySales,
    required this.completedOrders,
    required this.cancelledOrders,
    this.totalCogs = 0,
    this.grossProfit = 0,
    this.totalTaxCollected = 0,
    this.totalDiscount = 0,
    this.discountByStaff = const {},
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
    totalCogs: 0,
    grossProfit: 0,
    totalTaxCollected: 0,
    totalDiscount: 0,
    discountByStaff: {},
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

enum ReportTab { daily, shifts, auditLog }

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final reportTabProvider = StateProvider<ReportTab>((ref) => ReportTab.daily);

// ── Date range ────────────────────────────────────────────────────────────────

enum RangePreset { day, week, month, custom }

class DateRange {
  final DateTime start;
  final DateTime end;
  final RangePreset preset;
  const DateRange({
    required this.start,
    required this.end,
    required this.preset,
  });

  bool get isSingleDay =>
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;

  int get dayCount => end.difference(start).inDays + 1;
}

final dateRangeProvider = StateProvider<DateRange>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateRange(start: today, end: today, preset: RangePreset.day);
});

// ── Heatmap provider ──────────────────────────────────────────────────────────
final heatmapProvider =
    FutureProvider.family<WeeklyHeatmap, DateRange>((ref, range) async {
  if (range.isSingleDay) return WeeklyHeatmap.empty;
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return WeeklyHeatmap.empty;
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) return WeeklyHeatmap.empty;

  try {
    final client = ref.watch(supabaseClientProvider);
    final start = DateTime(range.start.year, range.start.month, range.start.day)
        .toUtc().toIso8601String();
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59)
        .toUtc().toIso8601String();

    final rows = await client
        .from('orders')
        .select('created_at, total_amount')
        .eq('business_id', businessId)
        .eq('status', 'completed')
        .gte('created_at', start)
        .lte('created_at', end);

    // 7 × 24 accumulator: key = weekday * 100 + hour
    final Map<int, double> amountMap = {};
    final Map<int, int> countMap = {};

    for (final o in (rows as List)) {
      final dt = DateTime.tryParse(o['created_at'] as String? ?? '')?.toLocal();
      if (dt == null) continue;
      final amount = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      final key = dt.weekday * 100 + dt.hour;
      amountMap[key] = (amountMap[key] ?? 0) + amount;
      countMap[key] = (countMap[key] ?? 0) + 1;
    }

    final cells = <HeatmapCell>[];
    double maxAmount = 0;
    for (var wd = 1; wd <= 7; wd++) {
      for (var h = 0; h < 24; h++) {
        final key = wd * 100 + h;
        final amt = amountMap[key] ?? 0;
        if (amt > maxAmount) maxAmount = amt;
        cells.add(HeatmapCell(
          weekday: wd,
          hour: h,
          amount: amt,
          orderCount: countMap[key] ?? 0,
        ));
      }
    }

    return WeeklyHeatmap(cells: cells, maxAmount: maxAmount);
  } catch (_) {
    return WeeklyHeatmap.empty;
  }
});

// Slow movers threshold — user-adjustable, persists in provider state
final slowMoverThresholdProvider = StateProvider<int>((ref) => 3);

// All products with their sales data for the selected date/range
// Returns products from inventory that had zero or low sales
final slowMoversProvider =
    FutureProvider.family<List<TopProduct>, ({DateRange range, int threshold})>(
        (ref, args) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return [];
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) return [];

  try {
    final client = ref.watch(supabaseClientProvider);
    final start =
        DateTime(args.range.start.year, args.range.start.month, args.range.start.day)
            .toUtc()
            .toIso8601String();
    final end = DateTime(args.range.end.year, args.range.end.month,
            args.range.end.day, 23, 59, 59)
        .toUtc()
        .toIso8601String();

    // Fetch all active products
    final products = await client
        .from('products')
        .select('id, name, category_name, cost_price, price')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');

    // Fetch sales in range
    final orders = await client
        .from('orders')
        .select('order_items(product_id, product_name, quantity, subtotal, cost_at_sale)')
        .eq('business_id', businessId)
        .eq('status', 'completed')
        .gte('created_at', start)
        .lte('created_at', end);

    // Aggregate sold qty by product id
    final Map<String, _ProductAccum> soldMap = {};
    for (final order in (orders as List)) {
      for (final item in (order['order_items'] as List? ?? [])) {
        final pid = item['product_id'] as String? ?? '';
        final name = item['product_name'] as String? ?? '';
        final qty = item['quantity'] as int? ?? 0;
        final sub = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
        final cost =
            ((item['cost_at_sale'] as num?)?.toDouble() ?? 0.0) * qty;
        final acc = soldMap[pid];
        soldMap[pid] = acc != null
            ? _ProductAccum(name, acc.qty + qty, acc.revenue + sub, acc.cogs + cost, '')
            : _ProductAccum(name, qty, sub, cost, '');
      }
    }

    // Find products at or below threshold
    final result = <TopProduct>[];
    for (final p in (products as List)) {
      final pid = p['id'] as String;
      final acc = soldMap[pid];
      final qtySold = acc?.qty ?? 0;
      if (qtySold <= args.threshold) {
        final revenue = acc?.revenue ?? 0.0;
        final cogs = acc?.cogs ?? 0.0;
        final gp = revenue - cogs;
        result.add(TopProduct(
          p['name'] as String,
          qtySold,
          revenue,
          cogs: cogs,
          grossProfit: gp,
          marginPct: revenue > 0 ? (gp / revenue * 100) : 0,
          category: (p['category_name'] as String?) ?? '',
        ));
      }
    }

    result.sort((a, b) => a.qty.compareTo(b.qty));
    return result;
  } catch (_) {
    return [];
  }
});

final periodReportProvider =
    FutureProvider.family<DailyReport, DateRange>((ref, range) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return DailyReport.empty;
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) {
    // For multi-day ranges, sum up cached daily rows
    final local = ref.read(localDbServiceProvider);
    String dateKey(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final cached = await local.getReports(
      businessId,
      fromDate: dateKey(range.start),
      toDate: dateKey(range.end),
    );
    if (cached.isEmpty) return DailyReport.empty.copyWith(isFromCache: true);
    double totalRevenue = 0;
    int totalOrders = 0;
    double totalCogs = 0;
    final List<TopProduct> topProducts = [];
    for (final row in cached) {
      totalRevenue += (row['total_sales'] as num?)?.toDouble() ?? 0;
      totalOrders += (row['order_count'] as int?) ?? 0;
      final rawTop = (row['top_products'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final p in rawTop) {
        totalCogs += (p['cogs'] as num?)?.toDouble() ?? 0;
        topProducts.add(TopProduct(
          p['name'] as String,
          (p['qty'] as num).toInt(),
          (p['revenue'] as num).toDouble(),
          cogs: (p['cogs'] as num?)?.toDouble() ?? 0,
          grossProfit: (p['gross_profit'] as num?)?.toDouble() ?? 0,
          marginPct: (p['margin_pct'] as num?)?.toDouble() ?? 0,
          category: p['category'] as String? ?? '',
        ));
      }
    }
    return DailyReport(
      totalRevenue: totalRevenue,
      totalOrders: totalOrders,
      avgOrderValue: totalOrders > 0 ? totalRevenue / totalOrders : 0,
      revenueByPayment: const {},
      topProducts: topProducts,
      hourlySales: List.generate(24, (h) => HourlySale(h, 0)),
      completedOrders: totalOrders,
      cancelledOrders: 0,
      totalCogs: totalCogs,
      grossProfit: totalRevenue - totalCogs,
      isFromCache: true,
    );
  }
  try {
    final client = ref.watch(supabaseClientProvider);
    final start = DateTime(range.start.year, range.start.month, range.start.day)
        .toUtc()
        .toIso8601String();
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59)
        .toUtc()
        .toIso8601String();

    final rows = await client
        .from('orders')
        .select(
            '*, order_items(product_name, quantity, subtotal, cost_at_sale, products(category_name)), staff_members(name)')
        .eq('business_id', businessId)
        .gte('created_at', start)
        .lte('created_at', end)
        .order('created_at');

    return _buildReport(rows as List, fromCache: false);
  } catch (e) {
    return DailyReport.empty;
  }
});

final dailyReportProvider =
    FutureProvider.family<DailyReport, DateTime>((ref, date) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return DailyReport.empty;
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
        .select('*, order_items(product_name, quantity, subtotal, cost_at_sale), staff_members(name)')
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
          .map((p) => {
                'name': p.name,
                'qty': p.qty,
                'revenue': p.revenue,
                'cogs': p.cogs,
                'gross_profit': p.grossProfit,
                'margin_pct': p.marginPct,
                'category': p.category,
              })
          .toList(),
    );

    return report;
  } catch (e) {
    return _loadFromCache(local, businessId, dateKey);
  }
});

final shiftReportProvider =
    FutureProvider.family<List<ShiftEntry>, DateTime>((ref, date) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return [];

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
              cogs: (p['cogs'] as num?)?.toDouble() ?? 0,
              grossProfit: (p['gross_profit'] as num?)?.toDouble() ?? 0,
              marginPct: (p['margin_pct'] as num?)?.toDouble() ?? 0,
              category: p['category'] as String? ?? '',
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
  double totalCogs = 0;
  double totalTax = 0;
  double totalDiscount = 0;
  final Map<String, double> discountByStaff = {};
  int completed = 0;
  int cancelled = 0;
  final Map<String, double> byPayment = {};
  final Map<String, _ProductAccum> productAccum = {};
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
      totalTax += (row['tax_amount'] as num?)?.toDouble() ?? 0.0;
      final disc = (row['discount_amount'] as num?)?.toDouble() ?? 0.0;
      totalDiscount += disc;
      if (disc > 0) {
        final staffRow = row['staff_members'] as Map<String, dynamic>?;
        final cashier = staffRow?['name'] as String? ??
            row['cashier_id'] as String? ?? 'Unknown';
        discountByStaff[cashier] =
            (discountByStaff[cashier] ?? 0) + disc;
      }
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
        final itemCost = ((item['cost_at_sale'] as num?)?.toDouble() ?? 0.0) * qty;
        final categoryRow = item['products'] as Map<String, dynamic>?;
        final category = categoryRow?['category_name'] as String? ?? '';
        if (isPaid) totalCogs += itemCost;
        final acc = productAccum[name];
        productAccum[name] = acc != null
            ? _ProductAccum(name, acc.qty + qty, acc.revenue + sub,
                acc.cogs + itemCost, acc.category)
            : _ProductAccum(name, qty, sub, itemCost, category);
      }
  }

  final grossProfit = totalRevenue - totalCogs;

  final topProducts = productAccum.values.map((a) {
    final gp = a.revenue - a.cogs;
    return TopProduct(
      a.name,
      a.qty,
      a.revenue,
      cogs: a.cogs,
      grossProfit: gp,
      marginPct: a.revenue > 0 ? (gp / a.revenue * 100) : 0,
      category: a.category,
    );
  }).toList()
    ..sort((a, b) => b.qty.compareTo(a.qty));

  return DailyReport(
    totalRevenue: totalRevenue,
    totalOrders: completed,
    avgOrderValue: completed > 0 ? totalRevenue / completed : 0,
    revenueByPayment: byPayment,
    topProducts: topProducts,
    hourlySales: List.generate(24, (h) => HourlySale(h, hourMap[h] ?? 0)),
    completedOrders: completed,
    cancelledOrders: cancelled,
    totalCogs: totalCogs,
    grossProfit: grossProfit,
    totalTaxCollected: totalTax,
    totalDiscount: totalDiscount,
    discountByStaff: discountByStaff,
    isFromCache: fromCache,
  );
}

class _ProductAccum {
  final String name;
  final int qty;
  final double revenue;
  final double cogs;
  final String category;
  const _ProductAccum(
      this.name, this.qty, this.revenue, this.cogs, this.category);
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
      where: 'business_id = ? AND cashier_id = ? AND status = ? '
            'AND created_at >= ? AND created_at <= ?',
      whereArgs: [businessId, staffId, 'completed',
                  from.toIso8601String(), to.toIso8601String()],
    );
    if (orders.isEmpty) return (0, 0);

    // Parameterized IN clause — no string interpolation
    final ids = orders.map((o) => o['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final items = await db.rawQuery(
      'SELECT SUM(quantity) as total FROM order_items '
      'WHERE order_id IN ($placeholders)',
      ids, // passed as args, not interpolated
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
    double? totalCogs,
    double? grossProfit,
    double? totalTaxCollected,
    double? totalDiscount,
    Map<String, double>? discountByStaff,
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
        totalCogs: totalCogs ?? this.totalCogs,
        grossProfit: grossProfit ?? this.grossProfit,
        totalTaxCollected: totalTaxCollected ?? this.totalTaxCollected,
        totalDiscount: totalDiscount ?? this.totalDiscount,
        discountByStaff: discountByStaff ?? this.discountByStaff,
        isFromCache: isFromCache ?? this.isFromCache,
        cachedAt: cachedAt ?? this.cachedAt,
      );
}
// ─────────────────────────────────────────────────────────────────────────────
// AUDIT LOG MODELS + PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class AuditLogEntry {
  final String id;
  final String performedByName;
  final String performedByRole;
  final String? authorisedByName;
  final String actionType;
  final String? entityType;
  final String? entityId;
  final String description;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.id,
    required this.performedByName,
    required this.performedByRole,
    required this.actionType,
    required this.description,
    required this.createdAt,
    this.authorisedByName,
    this.entityType,
    this.entityId,
    this.metadata,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> m) => AuditLogEntry(
        id:                m['id'] as String,
        performedByName:   m['performed_by_staff_name'] as String,
        performedByRole:   m['performed_by_role'] as String,
        authorisedByName:  m['authorised_by_staff_name'] as String?,
        actionType:        m['action_type'] as String,
        entityType:        m['entity_type'] as String?,
        entityId:          m['entity_id'] as String?,
        description:       m['description'] as String,
        metadata:          m['metadata'] as Map<String, dynamic>?,
        createdAt:         DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

// Filter state for the audit log viewer
class AuditFilter {
  final String? actionType;
  final String? staffName;
  final DateTime? from;
  final DateTime? to;

  const AuditFilter({
    this.actionType,
    this.staffName,
    this.from,
    this.to,
  });

  AuditFilter copyWith({
    Object? actionType = _sentinel,
    Object? staffName = _sentinel,
    Object? from = _sentinel,
    Object? to = _sentinel,
  }) =>
      AuditFilter(
        actionType: actionType == _sentinel
            ? this.actionType
            : actionType as String?,
        staffName:
            staffName == _sentinel ? this.staffName : staffName as String?,
        from: from == _sentinel ? this.from : from as DateTime?,
        to: to == _sentinel ? this.to : to as DateTime?,
      );
}

const _sentinel = Object();

final auditFilterProvider = StateProvider<AuditFilter>(
  (_) => const AuditFilter(),
);

final auditLogProvider =
    FutureProvider.family<List<AuditLogEntry>, AuditFilter>(
        (ref, filter) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return [];
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) return [];

  try {
    final client = ref.watch(supabaseClientProvider);
    var query = client
        .from('audit_logs')
        .select()
        .eq('business_id', businessId);

    if (filter.actionType != null) {
      query = query.eq('action_type', filter.actionType!);
    }
    if (filter.staffName != null && filter.staffName!.isNotEmpty) {
      query = query.ilike(
          'performed_by_staff_name', '%${filter.staffName}%');
    }
    if (filter.from != null) {
      query = query.gte('created_at',
          filter.from!.toUtc().toIso8601String());
    }
    if (filter.to != null) {
      query = query.lte(
          'created_at',
          DateTime(filter.to!.year, filter.to!.month, filter.to!.day,
                  23, 59, 59)
              .toUtc()
              .toIso8601String());
    }

    final rows = await query
        .order('created_at', ascending: false)
        .limit(200);

    return (rows as List)
        .map((r) => AuditLogEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});