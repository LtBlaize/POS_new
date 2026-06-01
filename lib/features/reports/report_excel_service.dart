// features/reports/report_excel_service.dart
//
// Builds the POS Excel report entirely in Dart — no template asset required.
// Uses Excel.createExcel(), writes headers + formulas + data from scratch.
//
// ── Sheets created ────────────────────────────────────────────────────────────
//   ⚙ Settings      business config values
//   📊 Sales Report  order line items
//   📦 Inventory     product catalogue
//   💸 Expenses      expense rows
//   👥 Payroll       shift-derived payroll
//   🏆 Performance   attendance & rating per staff
//   🚚 Suppliers     supplier purchase records
//   💰 Cash Flow     one row per cashier shift
//
// ── Formula columns (written by this service, not overwritten) ────────────────
//   Sales      I  = total amount   M = profit/item   N = total profit
//   Inventory  J  = stock status   K = inventory value
//   Payroll    H  = OT pay         I = gross salary   N = net salary
//   Performance B = total sales    C = txn count      D = avg sale
//              G  = perf score     H = rank
//   Suppliers  F  = total amount
//   Cash Flow  H  = closing balance

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../config/business_config.dart' hide settingsProvider;
import '../auth/auth_provider.dart';
import '../settings/settings_provider.dart';
import 'reports_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

final reportExcelServiceProvider = Provider<ReportExcelService>(
  (ref) => ReportExcelService(ref),
);

// ─────────────────────────────────────────────────────────────────────────────
// PAYROLL DEFAULTS
// ─────────────────────────────────────────────────────────────────────────────

const _kDailyRate           = 500.0;
const _kOvertimeMultiplier  = 1.25;
const _kSssDeduction        = 500.0;
const _kPhilhealthDeduction = 250.0;
const _kPagibigDeduction    = 100.0;
const _kLatePenaltyPerMin   = 2.0;
const _kExpiryWarningDays   = 30;

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL ROW MODELS
// ─────────────────────────────────────────────────────────────────────────────

class _SalesRow {
  final DateTime date;
  final String invoiceNumber, productName, category,
      paymentMethod, cashier, customerName;
  final int qtySold;
  final double unitPrice, discountPercent, taxPercent;
  const _SalesRow({
    required this.date, required this.invoiceNumber,
    required this.productName, required this.category,
    required this.qtySold, required this.unitPrice,
    required this.discountPercent, required this.taxPercent,
    required this.paymentMethod, required this.cashier,
    required this.customerName,
  });
}

class _InventoryRow {
  final String productId, barcode, productName, category, supplier;
  final double costPrice, sellingPrice;
  final int currentStock, minStockLevel;
  final DateTime? expiryDate;
  const _InventoryRow({
    required this.productId, required this.barcode,
    required this.productName, required this.category,
    required this.supplier, required this.costPrice,
    required this.sellingPrice, required this.currentStock,
    required this.minStockLevel, this.expiryDate,
  });
}

class _ExpenseRow {
  final DateTime date;
  final String category, description, vendor, paymentMethod, approvedBy;
  final double amount;
  const _ExpenseRow({
    required this.date, required this.category,
    required this.description, required this.vendor,
    required this.paymentMethod, required this.amount,
    required this.approvedBy,
  });
}

class _PayrollRow {
  final String empId, employeeName, position;
  final double dailyRate, otHours;
      
  final int attendanceDays, hoursWorked;
  const _PayrollRow({
    required this.empId, required this.employeeName,
    required this.position, required this.dailyRate,
    required this.attendanceDays, required this.hoursWorked,
    required this.otHours,
  });
}

class _PerformanceRow {
  final String employeeName;
  final double attendancePercent, customerRating;
  const _PerformanceRow({
    required this.employeeName,
    required this.attendancePercent,
    required this.customerRating,
  });
}

class _SupplierRow {
  final DateTime purchaseDate;
  final String supplierName, productPurchased, deliveryStatus, paymentStatus;
  final int quantity;
  final double unitCost;
  const _SupplierRow({
    required this.purchaseDate, required this.supplierName,
    required this.productPurchased, required this.quantity,
    required this.unitCost, required this.deliveryStatus,
    required this.paymentStatus,
  });
}

class _CashFlowRow {
  final DateTime date;
  final double openingBalance, cashInSales, cashOutExpenses,
      bankDeposit, withdrawal, pettyCash;
  const _CashFlowRow({
    required this.date, required this.openingBalance,
    required this.cashInSales, required this.cashOutExpenses,
    required this.bankDeposit, required this.withdrawal,
    required this.pettyCash,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class ReportExcelService {
  final Ref _ref;
  ReportExcelService(this._ref);

  Future<String> buildAndSave({
    required DateTime date,
    required DailyReport dailyReport,
    required List<ShiftEntry> shiftEntries,
    DateRange? dateRange,
  }) async {
    final profile    = await _ref.read(profileProvider.future);
    final businessId = profile?.businessId ?? '';
    final isOnline   = _ref.read(isOnlineProvider);
    final local      = _ref.read(localDbServiceProvider);
    final config     = _ref.read(settingsProvider).config;

    // ── Fetch data ──────────────────────────────────────────────────────────
    final rangeStart = dateRange?.start ?? date;
    final rangeEnd   = dateRange?.end   ?? date;
    final salesRows       = await _fetchSalesRowsRange(businessId, rangeStart, rangeEnd, isOnline, local, shiftEntries);
    final inventoryRows   = await _fetchInventoryRows(businessId, isOnline, local);
    final expenseRows     = await _fetchExpenseRowsRange(businessId, rangeStart, rangeEnd, isOnline, local, shiftEntries);
    final supplierRows    = await _fetchSupplierRowsRange(businessId, rangeStart, rangeEnd, isOnline);
    final payrollRows     = _buildPayrollRows(shiftEntries);
    final performanceRows = _buildPerformanceRows(shiftEntries);
    final cashFlowRows    = _buildCashFlowRows(shiftEntries);

    // ── Build workbook from scratch — no template, no decodeBytes ───────────
    final excel = Excel.createExcel();
    excel.delete('Sheet1'); // remove the auto-created default sheet

    _buildSettings(excel, config, date);
    _buildSalesReport(excel, salesRows);
    _buildInventory(excel, inventoryRows);
    _buildExpenses(excel, expenseRows);
    _buildPayroll(excel, payrollRows);
    _buildPerformance(excel, performanceRows);
    _buildSuppliers(excel, supplierRows);
    _buildCashFlow(excel, cashFlowRows);
    _buildTaxReport(excel, salesRows, dailyReport, date);
    _buildDiscountReport(excel, salesRows, dailyReport);

    // ── Save ────────────────────────────────────────────────────────────────
    final dir     = await getTemporaryDirectory();
    final suffix  = (dateRange != null && !dateRange.isSingleDay)
        ? '${_fmtDate(dateRange.start)}_to_${_fmtDate(dateRange.end)}'
        : _fmtDate(date);
    final path    = '${dir.path}/pos_report_$suffix.xlsx';
    final encoded = excel.encode();
    if (encoded == null) throw Exception('Excel encoding returned null');
    await File(path).writeAsBytes(encoded, flush: true);
    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA FETCHERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<_SalesRow>> _fetchSalesRowsRange(
    String businessId, DateTime start, DateTime end, bool isOnline,
    LocalDbService local, List<ShiftEntry> shiftEntries,
  ) async {
    return _fetchSalesRows(businessId, start, end, isOnline, local, shiftEntries);
  }

  Future<List<_SalesRow>> _fetchSalesRows(
    String businessId, DateTime start, DateTime end, bool isOnline,
    LocalDbService local, List<ShiftEntry> shiftEntries,
  ) async {
    final cashierNames = {
      for (final e in shiftEntries) e.shift.staffId: e.shift.staffName,
    };
    final dayStart = DateTime(start.year, start.month, start.day).toUtc().toIso8601String();
    final dayEnd   = DateTime(end.year, end.month, end.day, 23, 59, 59).toUtc().toIso8601String();

    List<Map<String, dynamic>> rows = [];
    if (isOnline) {
      try {
        final raw = await Supabase.instance.client
            .from('orders')
            .select('id, created_at, payment_method, cashier_id, cashier_name, '
                'customer_name, status, '
                'order_items(product_name, category, quantity, unit_price, discount_percent)')
            .eq('business_id', businessId)
            .eq('status', 'completed')
            .gte('created_at', dayStart)
            .lte('created_at', dayEnd)
            .order('created_at');
        rows = List<Map<String, dynamic>>.from(raw as List);
      } catch (_) {
        rows = await _localOrderRows(local, businessId, dayStart, dayEnd);
      }
    } else {
      rows = await _localOrderRows(local, businessId, dayStart, dayEnd);
    }

    final result = <_SalesRow>[];
    int seq = 1;
    for (final order in rows) {
      final createdAt   = DateTime.tryParse(order['created_at'] as String? ?? '')?.toLocal() ?? start;
      final payMethod   = _normalisePayment(order['payment_method'] as String? ?? 'cash');
      final cashierName = order['cashier_name'] as String? ??
          cashierNames[order['cashier_id'] as String? ?? ''] ?? 'Unknown';
      final customerName =
          (order['customer_name'] as String?)?.trim().isNotEmpty == true
              ? order['customer_name'] as String : 'Walk-in';
      final invoiceNo = 'INV-${seq.toString().padLeft(5, '0')}';
      seq++;
      for (final item in (order['order_items'] as List? ?? [])) {
        result.add(_SalesRow(
          date:            createdAt,
          invoiceNumber:   invoiceNo,
          productName:     item['product_name']     as String? ?? 'Unknown',
          category:        item['category']          as String? ?? 'Uncategorised',
          qtySold:         (item['quantity']         as num?)?.toInt()    ?? 1,
          unitPrice:       (item['unit_price']       as num?)?.toDouble() ?? 0,
          discountPercent: (item['discount_percent'] as num?)?.toDouble() ?? 0,
          taxPercent:      12.0,
          paymentMethod:   payMethod,
          cashier:         cashierName,
          customerName:    customerName,
        ));
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _localOrderRows(
    LocalDbService local, String businessId, String from, String to,
  ) async {
    final db = await local.db;
    return (await db.query(
      'orders',
      where:     'business_id = ? AND status = ? AND created_at >= ? AND created_at <= ?',
      whereArgs: [businessId, 'completed', from, to],
      orderBy:   'created_at ASC',
    )).cast<Map<String, dynamic>>();
  }

  Future<List<_InventoryRow>> _fetchInventoryRows(
    String businessId, bool isOnline, LocalDbService local,
  ) async {
    List<Map<String, dynamic>> rows = [];
    if (isOnline) {
      try {
        final raw = await Supabase.instance.client
            .from('products')
            .select('id, barcode, name, category, supplier, cost_price, price, stock, min_stock, expiry_date')
            .eq('business_id', businessId)
            .eq('is_active', true)
            .order('category').order('name');
        rows = List<Map<String, dynamic>>.from(raw as List);
      } catch (_) {
        rows = await _localProductRows(local, businessId);
      }
    } else {
      rows = await _localProductRows(local, businessId);
    }
    return rows.map((r) => _InventoryRow(
      productId:     r['id']             as String? ?? '',
      barcode:       r['barcode']        as String? ?? '',
      productName:   r['name']           as String? ?? '',
      // Supabase = 'category', SQLite = 'category_name'
      category:      (r['category'] ?? r['category_name']) as String? ?? '',
      supplier:      r['supplier']       as String? ?? '',
      costPrice:     (r['cost_price']    as num?)?.toDouble() ?? 0,
      sellingPrice:  (r['price']         as num?)?.toDouble() ?? 0,
      // Supabase = 'stock', SQLite = 'stock_quantity'
      currentStock:  ((r['stock'] ?? r['stock_quantity']) as num?)?.toInt() ?? 0,
      minStockLevel: (r['min_stock']     as num?)?.toInt() ?? 0,
      expiryDate:    r['expiry_date'] != null
          ? DateTime.tryParse(r['expiry_date'] as String) : null,
    )).toList();
  }

  Future<List<Map<String, dynamic>>> _localProductRows(
    LocalDbService local, String businessId,
  ) async {
    final db = await local.db;
    return (await db.query(
      'products',
      where:     'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy:   'category_name ASC, name ASC',
    )).cast<Map<String, dynamic>>();
  }

  Future<List<_ExpenseRow>> _fetchExpenseRowsRange(
    String businessId, DateTime start, DateTime end, bool isOnline,
    LocalDbService local, List<ShiftEntry> shiftEntries,
  ) => _fetchExpenseRows(businessId, start, end, isOnline, local, shiftEntries);

  Future<List<_ExpenseRow>> _fetchExpenseRows(
    String businessId, DateTime start, DateTime end, bool isOnline,
    LocalDbService local, List<ShiftEntry> shiftEntries,
  ) async {
    final dayStart = DateTime(start.year, start.month, start.day).toUtc().toIso8601String();
    final dayEnd   = DateTime(end.year, end.month, end.day, 23, 59, 59).toUtc().toIso8601String();
    if (isOnline) {
      try {
        final raw = await Supabase.instance.client
            .from('expenses')
            .select('created_at, category, description, vendor, payment_method, amount, approved_by')
            .eq('business_id', businessId)
            .gte('created_at', dayStart).lte('created_at', dayEnd)
            .order('created_at');
        final rows = List<Map<String, dynamic>>.from(raw as List);
        if (rows.isNotEmpty) {
          return rows.map((r) => _ExpenseRow(
            date:          DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ?? start,
            category:      r['category']    as String? ?? 'Operations',
            description:   r['description'] as String? ?? '',
            vendor:        r['vendor']      as String? ?? '',
            paymentMethod: _normalisePayment(r['payment_method'] as String? ?? 'cash'),
            amount:        (r['amount']     as num?)?.toDouble() ?? 0,
            approvedBy:    r['approved_by'] as String? ?? 'Manager',
          )).toList();
        }
      } catch (_) {}
    }
    return shiftEntries.where((e) => e.shift.expenses > 0).map((e) => _ExpenseRow(
      date:          e.shift.openedAt,
      category:      'Operations',
      description:   'Shift expenses — ${e.shift.staffName}',
      vendor:        '',
      paymentMethod: 'Cash',
      amount:        e.shift.expenses,
      approvedBy:    e.shift.staffName,
    )).toList();
  }

  Future<List<_SupplierRow>> _fetchSupplierRowsRange(
    String businessId, DateTime start, DateTime end, bool isOnline,
  ) => _fetchSupplierRows(businessId, start, end, isOnline);

  Future<List<_SupplierRow>> _fetchSupplierRows(
    String businessId, DateTime start, DateTime end, bool isOnline,
  ) async {
    if (!isOnline) return [];
    final dayStart = DateTime(start.year, start.month, start.day).toUtc().toIso8601String();
    final dayEnd   = DateTime(end.year, end.month, end.day, 23, 59, 59).toUtc().toIso8601String();
    try {
      final raw = await Supabase.instance.client
          .from('supplier_purchases')
          .select('purchase_date, supplier_name, product_name, quantity, unit_cost, delivery_status, payment_status')
          .eq('business_id', businessId)
          .gte('purchase_date', dayStart).lte('purchase_date', dayEnd)
          .order('purchase_date');
      return (raw as List).cast<Map<String, dynamic>>().map((r) => _SupplierRow(
        purchaseDate:     DateTime.tryParse(r['purchase_date'] as String? ?? '')?.toLocal() ?? start,
        supplierName:     r['supplier_name']   as String? ?? '',
        productPurchased: r['product_name']    as String? ?? '',
        quantity:         (r['quantity']        as num?)?.toInt()    ?? 0,
        unitCost:         (r['unit_cost']       as num?)?.toDouble() ?? 0,
        deliveryStatus:   r['delivery_status'] as String? ?? 'Delivered',
        paymentStatus:    r['payment_status']  as String? ?? 'Paid',
      )).toList();
    } catch (_) { return []; }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DERIVERS
  // ─────────────────────────────────────────────────────────────────────────

  List<_PayrollRow> _buildPayrollRows(List<ShiftEntry> entries) {
    final byStaff = <String, List<ShiftEntry>>{};
    for (final e in entries) {
      byStaff.putIfAbsent(e.shift.staffId, () => []).add(e);
    }
    return byStaff.entries.map((kv) {
      final first        = kv.value.first.shift;
      final totalMinutes = kv.value.fold<int>(0, (s, e) => s + e.duration.inMinutes);
      final totalHours   = totalMinutes / 60.0;
      final days         = kv.value.length;
      final regularHours = (8.0 * days).clamp(0.0, totalHours);
      final otHours      = (totalHours - regularHours).clamp(0.0, double.infinity);
      return _PayrollRow(
        empId: first.staffId, employeeName: first.staffName, position: 'Cashier',
        dailyRate: _kDailyRate, attendanceDays: days,
        hoursWorked: regularHours.round(), otHours: otHours,
      );
    }).toList();
  }

  List<_PerformanceRow> _buildPerformanceRows(List<ShiftEntry> entries) {
    final seen = <String>{};
    final result = <_PerformanceRow>[];
    for (final e in entries) {
      if (!seen.add(e.shift.staffId)) continue;
      final days = entries.where((x) => x.shift.staffId == e.shift.staffId).length;
      result.add(_PerformanceRow(
        employeeName:      e.shift.staffName,
        attendancePercent: (days / 26 * 100).clamp(0.0, 100.0),
        customerRating:    4.5,
      ));
    }
    return result;
  }

  List<_CashFlowRow> _buildCashFlowRows(List<ShiftEntry> entries) {
    return ([...entries]..sort((a, b) => a.shift.openedAt.compareTo(b.shift.openedAt)))
        .map((e) => _CashFlowRow(
              date:            e.shift.openedAt,
              openingBalance:  e.shift.openingCash,
              cashInSales:     e.shift.cashSales,
              cashOutExpenses: e.shift.expenses,
              bankDeposit: 0, withdrawal: 0, pettyCash: 0,
            ))
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHEET BUILDERS
  // rowIndex is always 0-based; er (Excel row) = rowIndex + 1 for formulas.
  // Data starts at rowIndex 4 (Excel row 5).
  // ─────────────────────────────────────────────────────────────────────────

  void _buildSettings(Excel excel, BusinessConfig? cfg, DateTime date) {
    final sh = excel['⚙ Settings'];
    _wh(sh, 0, 0, '⚙  BUSINESS SETTINGS & CONFIGURATION');
    _wh(sh, 3,  0, 'BUSINESS INFORMATION');
    _wh(sh, 10, 0, 'FINANCIAL SETTINGS');
    _wh(sh, 17, 0, 'REPORT SETTINGS');

    const bizLabels = ['Business Name','Address','Phone','Email','Tax / Business ID','Currency Symbol'];
    for (var i = 0; i < bizLabels.length; i++) {
      _ws(sh, 4 + i, 1, bizLabels[i]);
    }
    _ws(sh, 4, 2, ''); _ws(sh, 5, 2, ''); _ws(sh, 6, 2, '');
    _ws(sh, 7, 2, ''); _ws(sh, 8, 2, ''); _ws(sh, 9, 2, '₱');

    const finLabels = ['VAT Rate (%)','Overtime Multiplier','Late Penalty/Minute',
                       'SSS Deduction','PhilHealth Deduction','Pag-IBIG Deduction'];
    for (var i = 0; i < finLabels.length; i++) {
      _ws(sh, 11 + i, 1, finLabels[i]);
    }
    _wd(sh, 11, 2, cfg?.taxRate ?? 0.0);
    _wd(sh, 12, 2, _kOvertimeMultiplier);
    _wd(sh, 13, 2, _kLatePenaltyPerMin);
    _wd(sh, 14, 2, _kSssDeduction);
    _wd(sh, 15, 2, _kPhilhealthDeduction);
    _wd(sh, 16, 2, _kPagibigDeduction);

    const repLabels = ['Report Start Date','Report End Date','Fiscal Year',
                       'Low Stock Threshold','Expiry Warning Days'];
    for (var i = 0; i < repLabels.length; i++) {
      _ws(sh, 18 + i, 1, repLabels[i]);
    }
    _ws(sh, 18, 2, _fmtDate(date));
    _ws(sh, 19, 2, _fmtDate(date));
    _wi(sh, 20, 2, date.year);
    _wi(sh, 21, 2, cfg?.lowStockThreshold ?? 5);
    _wi(sh, 22, 2, _kExpiryWarningDays);
  }

  void _buildSalesReport(Excel excel, List<_SalesRow> rows) {
    final sh = excel['📊 Sales Report'];
    _wh(sh, 0, 0, '📊  DAILY SALES REPORT');
    _writeHeaders(sh, 3, ['Date','Invoice #','Product Name','Category','Qty Sold',
      'Unit Price','Discount (%)','Tax (%)','Total Amount','Payment Method',
      'Cashier','Customer Name','Profit/Item','Total Profit']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final er = r + 1; final l = rows[i];
      _ws(sh, r, 0,  _fmtDate(l.date));
      _ws(sh, r, 1,  l.invoiceNumber);
      _ws(sh, r, 2,  l.productName);
      _ws(sh, r, 3,  l.category);
      _wi(sh, r, 4,  l.qtySold);
      _wd(sh, r, 5,  l.unitPrice);
      _wd(sh, r, 6,  l.discountPercent);
      _wd(sh, r, 7,  l.taxPercent);
      _wf(sh, r, 8,  'E$er*F$er*(1-G$er/100)*(1+H$er/100)');
      _ws(sh, r, 9,  l.paymentMethod);
      _ws(sh, r, 10, l.cashier);
      _ws(sh, r, 11, l.customerName);
      _wf(sh, r, 12, 'F$er*(1-G$er/100)');
      _wf(sh, r, 13, 'M$er*E$er');
    }
  }

  void _buildInventory(Excel excel, List<_InventoryRow> rows) {
    final sh = excel['📦 Inventory'];
    _wh(sh, 0, 0, '📦  PRODUCT INVENTORY MANAGEMENT');
    _writeHeaders(sh, 3, ['Product ID','Barcode','Product Name','Category','Supplier',
      'Cost Price','Selling Price','Current Stock','Min Stock Level',
      'Stock Status','Inventory Value','Expiry Date']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final er = r + 1; final l = rows[i];
      _ws(sh, r, 0,  l.productId);
      _ws(sh, r, 1,  l.barcode);
      _ws(sh, r, 2,  l.productName);
      _ws(sh, r, 3,  l.category);
      _ws(sh, r, 4,  l.supplier);
      _wd(sh, r, 5,  l.costPrice);
      _wd(sh, r, 6,  l.sellingPrice);
      _wi(sh, r, 7,  l.currentStock);
      _wi(sh, r, 8,  l.minStockLevel);
      _wf(sh, r, 9,  'IF(H$er=0,"OUT OF STOCK",IF(H$er<=I$er,"LOW STOCK","In Stock"))');
      _wf(sh, r, 10, 'H$er*G$er');
      if (l.expiryDate != null) _ws(sh, r, 11, _fmtDate(l.expiryDate!));
    }
  }

  void _buildExpenses(Excel excel, List<_ExpenseRow> rows) {
    final sh = excel['💸 Expenses'];
    _wh(sh, 0, 0, '💸  EXPENSE TRACKING SHEET');
    _writeHeaders(sh, 3, ['Date','Expense Category','Description',
      'Supplier/Vendor','Payment Method','Amount','Approved By']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final l = rows[i];
      _ws(sh, r, 0, _fmtDate(l.date));
      _ws(sh, r, 1, l.category);
      _ws(sh, r, 2, l.description);
      _ws(sh, r, 3, l.vendor);
      _ws(sh, r, 4, l.paymentMethod);
      _wd(sh, r, 5, l.amount);
      _ws(sh, r, 6, l.approvedBy);
    }
  }

  void _buildPayroll(Excel excel, List<_PayrollRow> rows) {
    final sh = excel['👥 Payroll'];
    _wh(sh, 0, 0, '👥  PAYROLL & SALARY CALCULATION');
    _writeHeaders(sh, 3, ['Emp ID','Employee Name','Position','Daily Rate',
      'Attendance Days','Hours Worked','OT Hours','OT Pay','Gross Salary',
      'SSS','PhilHealth','Pag-IBIG','Late Penalty','Net Salary']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final er = r + 1; final l = rows[i];
      _ws(sh, r, 0,  l.empId);
      _ws(sh, r, 1,  l.employeeName);
      _ws(sh, r, 2,  l.position);
      _wd(sh, r, 3,  l.dailyRate);
      _wi(sh, r, 4,  l.attendanceDays);
      _wi(sh, r, 5,  l.hoursWorked);
      _wd(sh, r, 6,  l.otHours);
      _wf(sh, r, 7,  'ROUND((D$er/8)*1.25*G$er,2)');
      _wf(sh, r, 8,  'D$er*E$er+H$er');
      _wd(sh, r, 12, 0.0);
      _wf(sh, r, 13, 'I$er-J$er-K$er-L$er-M$er');
    }
  }

  void _buildPerformance(Excel excel, List<_PerformanceRow> rows) {
    final sh      = excel['🏆 Performance'];
    final kRef    = "'📊 Sales Report'!\$K\$5:\$K\$5000";
    final iRef    = "'📊 Sales Report'!\$I\$5:\$I\$5000";
    final lastEr  = 4 + rows.length + 1; // Excel row of last data row + 1 for MAX range
    _wh(sh, 0, 0, '🏆  EMPLOYEE PERFORMANCE TRACKER');
    _writeHeaders(sh, 3, ['Employee Name','Total Sales','Transactions','Avg Sale',
      'Attendance %','Customer Rating','Performance Score','Rank']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final er = r + 1; final l = rows[i];
      _ws(sh, r, 0, l.employeeName);
      _wf(sh, r, 1, 'SUMIF($kRef,A$er,$iRef)');
      _wf(sh, r, 2, 'COUNTIF($kRef,A$er)');
      _wf(sh, r, 3, 'IFERROR(B$er/C$er,0)');
      _wd(sh, r, 4, l.attendancePercent);
      _wd(sh, r, 5, l.customerRating);
      _wf(sh, r, 6,
          'ROUND((B$er/MAX(\$B\$5:\$B\$$lastEr)*40)'
          '+(C$er/MAX(\$C\$5:\$C\$$lastEr)*30)'
          '+(F$er/5*30),1)');
      _wf(sh, r, 7, 'RANK(G$er,\$G\$5:\$G\$$lastEr,0)');
    }
  }

  void _buildSuppliers(Excel excel, List<_SupplierRow> rows) {
    final sh = excel['🚚 Suppliers'];
    _wh(sh, 0, 0, '🚚  SUPPLIER & PURCHASE RECORDS');
    _writeHeaders(sh, 3, ['Purchase Date','Supplier Name','Product Purchased',
      'Quantity','Unit Cost','Total Amount','Delivery Status','Payment Status']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final er = r + 1; final l = rows[i];
      _ws(sh, r, 0, _fmtDate(l.purchaseDate));
      _ws(sh, r, 1, l.supplierName);
      _ws(sh, r, 2, l.productPurchased);
      _wi(sh, r, 3, l.quantity);
      _wd(sh, r, 4, l.unitCost);
      _wf(sh, r, 5, 'D$er*E$er');
      _ws(sh, r, 6, l.deliveryStatus);
      _ws(sh, r, 7, l.paymentStatus);
    }
  }

  void _buildDiscountReport(
    Excel excel,
    List<_SalesRow> salesRows,
    DailyReport report,
  ) {
    final sh = excel['💳 Discounts'];
    _wh(sh, 0, 0, '💳  DISCOUNT & PROMO REPORT');

    // ── Summary ────────────────────────────────────────────────────────────
    _wh(sh, 2, 0, 'SUMMARY');
    _ws(sh, 3, 0, 'Total Discounts Given');
    _wd(sh, 3, 1, report.totalDiscount);
    _ws(sh, 4, 0, 'Total Revenue');
    _wd(sh, 4, 1, report.totalRevenue);
    _ws(sh, 5, 0, 'Discount Rate');
    final rateCell = sh.cell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 5));
    rateCell.value = FormulaCellValue('IFERROR(B4/(B5+B4)*100,0)');

    // ── By cashier ─────────────────────────────────────────────────────────
    _wh(sh, 7, 0, 'BY CASHIER');
    _writeHeaders(sh, 8, ['Cashier', 'Total Discount', 'Share (%)']);
    final byStaff = report.discountByStaff.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var i = 0; i < byStaff.length; i++) {
      final r = 9 + i;
      final er = r + 1;
      _ws(sh, r, 0, byStaff[i].key);
      _wd(sh, r, 1, byStaff[i].value);
      _wf(sh, r, 2, 'IFERROR(B$er/\$B\$4*100,0)');
    }

    // ── Transaction detail ─────────────────────────────────────────────────
    final detailStart = 10 + byStaff.length + 2;
    _wh(sh, detailStart, 0, 'DISCOUNTED TRANSACTIONS');
    _writeHeaders(sh, detailStart + 1, [
      'Date', 'Invoice #', 'Product', 'Unit Price',
      'Qty', 'Discount (%)', 'Discount Amount', 'Cashier',
    ]);
    final discounted =
        salesRows.where((r) => r.discountPercent > 0).toList();
    for (var i = 0; i < discounted.length; i++) {
      final r = detailStart + 2 + i;
      final l = discounted[i];
      final discAmt =
          l.unitPrice * l.qtySold * (l.discountPercent / 100);
      _ws(sh, r, 0, _fmtDate(l.date));
      _ws(sh, r, 1, l.invoiceNumber);
      _ws(sh, r, 2, l.productName);
      _wd(sh, r, 3, l.unitPrice);
      _wi(sh, r, 4, l.qtySold);
      _wd(sh, r, 5, l.discountPercent);
      _wd(sh, r, 6, discAmt);
      _ws(sh, r, 7, l.cashier);
    }
  }

  void _buildTaxReport(
    Excel excel,
    List<_SalesRow> salesRows,
    DailyReport report,
    DateTime date,
  ) {
    final sh = excel['🧾 Tax Report'];
    _wh(sh, 0, 0, '🧾  TAX COLLECTION REPORT');

    // ── Summary block ──────────────────────────────────────────────────────
    _wh(sh, 2, 0, 'SUMMARY');
    _ws(sh, 3, 0, 'Report Date');
    _ws(sh, 3, 1, _fmtDate(date));
    _ws(sh, 4, 0, 'Gross Revenue (incl. tax)');
    _wd(sh, 4, 1, report.totalRevenue);
    _ws(sh, 5, 0, 'Total Tax Collected');
    _wd(sh, 5, 1, report.totalTaxCollected);
    _ws(sh, 6, 0, 'Net Revenue (excl. tax)');
    final sh6 = sh.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 6));
    sh6.value = FormulaCellValue('B5-B6');
    _ws(sh, 7, 0, 'Total Orders Taxed');
    _wi(sh, 7, 1, report.completedOrders);
    _ws(sh, 8, 0, 'Effective Tax Rate');
    final sh8 = sh.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8));
    sh8.value = FormulaCellValue('IFERROR(B6/B5*100,0)');

    // ── Per-transaction detail ─────────────────────────────────────────────
    _wh(sh, 11, 0, 'TRANSACTION DETAIL');
    _writeHeaders(sh, 12, [
      'Date', 'Invoice #', 'Product', 'Category',
      'Unit Price', 'Qty', 'Subtotal', 'Tax Rate (%)', 'Tax Amount', 'Payment Method',
    ]);

    for (var i = 0; i < salesRows.length; i++) {
      final r = 13 + i;
      final l = salesRows[i];
      final subtotal = l.unitPrice * l.qtySold * (1 - l.discountPercent / 100);
      final taxAmt = subtotal * (l.taxPercent / 100);
      _ws(sh, r, 0, _fmtDate(l.date));
      _ws(sh, r, 1, l.invoiceNumber);
      _ws(sh, r, 2, l.productName);
      _ws(sh, r, 3, l.category);
      _wd(sh, r, 4, l.unitPrice);
      _wi(sh, r, 5, l.qtySold);
      _wd(sh, r, 6, subtotal);
      _wd(sh, r, 7, l.taxPercent);
      _wd(sh, r, 8, taxAmt);
      _ws(sh, r, 9, l.paymentMethod);
    }

    // ── Totals row ─────────────────────────────────────────────────────────
    if (salesRows.isNotEmpty) {
      final totalRow = 13 + salesRows.length;
      final lastEr = totalRow; // last data Excel row
      _wh(sh, totalRow, 1, 'TOTALS');
      final subtotalCell = sh.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: totalRow));
      subtotalCell.value = FormulaCellValue('SUM(G14:G$lastEr)');
      subtotalCell.cellStyle = CellStyle(bold: true);
      final taxTotalCell = sh.cell(
          CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: totalRow));
      taxTotalCell.value = FormulaCellValue('SUM(I14:I$lastEr)');
      taxTotalCell.cellStyle = CellStyle(bold: true);
    }
  }

  void _buildCashFlow(Excel excel, List<_CashFlowRow> rows) {
    final sh = excel['💰 Cash Flow'];
    _wh(sh, 0, 0, '💰  DAILY CASH FLOW REGISTER');
    _writeHeaders(sh, 3, ['Date','Opening Balance','Cash In (Sales)',
      'Cash Out (Expenses)','Bank Deposit','Withdrawal','Petty Cash','Closing Balance']);
    for (var i = 0; i < rows.length; i++) {
      final r = 4 + i; final er = r + 1; final l = rows[i];
      _ws(sh, r, 0, _fmtDate(l.date));
      _wd(sh, r, 1, l.openingBalance);
      _wd(sh, r, 2, l.cashInSales);
      _wd(sh, r, 3, l.cashOutExpenses);
      _wd(sh, r, 4, l.bankDeposit);
      _wd(sh, r, 5, l.withdrawal);
      _wd(sh, r, 6, l.pettyCash);
      _wf(sh, r, 7, 'B$er+C$er-D$er-E$er+F$er-G$er');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CELL WRITERS  (all 0-based row / col)
  // ─────────────────────────────────────────────────────────────────────────

  void _writeHeaders(Sheet sh, int rowIndex, List<String> labels) {
    for (var ci = 0; ci < labels.length; ci++) {
      final c = sh.cell(CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: rowIndex));
      c.value = TextCellValue(labels[ci]);
      c.cellStyle = CellStyle(bold: true);
    }
  }

  void _wh(Sheet sh, int row, int col, String v) {
    final c = sh.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    c.value = TextCellValue(v);
    c.cellStyle = CellStyle(bold: true);
  }

  void _ws(Sheet sh, int row, int col, String v) => sh
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value = TextCellValue(v);

  void _wi(Sheet sh, int row, int col, int v) => sh
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value = IntCellValue(v);

  void _wd(Sheet sh, int row, int col, double v) => sh
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value = DoubleCellValue(v);

  void _wf(Sheet sh, int row, int col, String formula) => sh
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value = FormulaCellValue(formula);

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _fmtDate(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

  String _normalisePayment(String raw) {
    switch (raw.toLowerCase().replaceAll(RegExp(r'[\s_]'), '')) {
      case 'cash':        return 'Cash';
      case 'gcash':       return 'GCash';
      case 'paymaya':
      case 'maya':        return 'PayMaya';
      case 'creditcard':
      case 'credit':      return 'Credit Card';
      case 'debitcard':
      case 'debit':       return 'Debit Card';
      default:            return raw;
    }
  }
}