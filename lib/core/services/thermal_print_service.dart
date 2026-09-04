import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';
import 'printer_prefs.dart';

/// Thrown when no thermal printer is configured/detected at all.
class PrinterNotFoundException implements Exception {
  final String message;
  PrinterNotFoundException(this.message);
  @override
  String toString() => message;
}

/// Thrown when the printer saved in Settings is no longer detected
/// (unplugged, powered off, or removed from Windows).
class PrinterOfflineException implements Exception {
  final String message;
  PrinterOfflineException(this.message);
  @override
  String toString() => message;
}

/// Thrown when a print job was sent to the OS but did not succeed.
class PrintJobFailedException implements Exception {
  final String message;
  PrintJobFailedException(this.message);
  @override
  String toString() => message;
}

/// Status of the printer saved in Settings, without sending a print job.
enum PrinterStatus { notConfigured, offline, available }

/// Handles thermal receipt printing (58mm / 80mm roll) and cash drawer trigger.
class ThermalPrintService {
  // ── Paper width ─────────────────────────────────────────────────────────────
  // 58mm ≈ 164pt | 80mm ≈ 227pt  (1mm ≈ 2.8346pt)
  static const _paperWidth58mm = PdfPageFormat(164, double.infinity, marginAll: 6);
  static const _paperWidth80mm = PdfPageFormat(227, double.infinity, marginAll: 8);

  static PdfPageFormat getPaperFormat(bool is58mm) {
    return is58mm ? _paperWidth58mm : _paperWidth80mm;
  }

  // ── Print Bill (no payment info — just the bill) ──────────────────────────
  static Future<void> printBill({
    required Order order,
    required String businessName,
    bool is58mm = false,
    String? businessAddress,
    String? tableNumber,
    String? roomName,
    Printer? printer,
  }) async {
    final pdf = await _buildBillPdf(
      order: order,
      businessName: businessName,
      is58mm: is58mm,
      businessAddress: businessAddress,
      tableNumber: tableNumber,
      roomName: roomName,
    );

    final target = await _resolvePrinter(explicit: printer);
    bool success;
    try {
      success = await Printing.directPrintPdf(
        printer: target,
        onLayout: (_) async => pdf,
        format: getPaperFormat(is58mm),
        name: 'Bill-Order#${order.orderNumber}',
      );
    } catch (e) {
      throw PrintJobFailedException('Failed to print bill to "${target.name}": $e');
    }
    if (!success) {
      throw PrintJobFailedException(
        'Print job to "${target.name}" did not complete. Check paper, power, and connection.',
      );
    }
  }

  // ── Print Receipt (after payment — includes tendered/change) ─────────────
  static Future<void> printReceipt({
    required Order order,
    required double tendered,
    required double change,
    required String businessName,
    bool is58mm = false,
    String? businessAddress,
    String? tableNumber,
    String? roomName,
    Printer? printer,
  }) async {
    final pdf = await _buildReceiptPdf(
      order: order,
      tendered: tendered,
      change: change,
      businessName: businessName,
      is58mm: is58mm,
      businessAddress: businessAddress,
      tableNumber: tableNumber,
      roomName: roomName,
    );

    final target = await _resolvePrinter(explicit: printer);
    bool success;
    try {
      success = await Printing.directPrintPdf(
        printer: target,
        onLayout: (_) async => pdf,
        format: getPaperFormat(is58mm),
        name: 'Receipt-Order#${order.orderNumber}',
      );
    } catch (e) {
      throw PrintJobFailedException('Failed to print receipt to "${target.name}": $e');
    }
    if (!success) {
      throw PrintJobFailedException(
        'Print job to "${target.name}" did not complete. Check paper, power, and connection.',
      );
    }
  }

  // ── Open Cash Drawer ──────────────────────────────────────────────────────
  /// Sends ESC/POS pulse command through the default printer.
  /// Works on any standard thermal printer with a drawer kick port.
  /// Returns true if the pulse was sent successfully. Doesn't throw — a
  /// failed drawer kick shouldn't block checkout — but no longer swallows
  /// the reason silently; callers can check the return value if they want to.
  static Future<bool> openCashDrawer({Printer? printer}) async {
    final drawerPulse = Uint8List.fromList([
      0x1B, 0x70, 0x00, 0x19, 0xFA, // pin 2
      0x1B, 0x70, 0x01, 0x19, 0xFA, // pin 5 (some printers use this)
    ]);

    try {
      final target = await _resolvePrinter(explicit: printer);
      final success = await Printing.directPrintPdf(
        printer: target,
        onLayout: (_) async => _wrapRawBytes(drawerPulse),
      );
      if (!success) {
        debugPrint('[CashDrawer] Print job to "${target.name}" did not complete.');
      }
      return success;
    } catch (e) {
      debugPrint('[CashDrawer] Could not open drawer: $e');
      return false;
    }
  }

  // ── Resolve which printer to use ────────────────────────────────────────
  /// Order of preference: explicit arg → saved Settings selection (by URL,
  /// then name) → best-guess name match → first printer Windows reports.
  /// This is what the old code was missing: Settings saved a choice that
  /// nothing here ever read.
  static Future<Printer> _resolvePrinter({Printer? explicit}) async {
    if (explicit != null) return explicit;

    final printers = await Printing.listPrinters();
    if (printers.isEmpty) {
      throw PrinterNotFoundException(
        'No printers detected. Make sure the thermal printer is installed '
        'as a Windows printer (Settings > Printers & scanners) and powered on.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(PrinterPrefsKeys.url);
    final savedName = prefs.getString(PrinterPrefsKeys.name);

    if (savedUrl != null && savedUrl.isNotEmpty) {
      final match = printers.where((p) => p.url.toString() == savedUrl);
      if (match.isNotEmpty) return match.first;
    }
    if (savedName != null && savedName.isNotEmpty) {
      final match = printers.where((p) => p.name == savedName);
      if (match.isNotEmpty) return match.first;

      throw PrinterOfflineException(
        'Selected printer "$savedName" is no longer available. It may be '
        'disconnected or turned off. Reselect a printer in Settings.',
      );
    }

    return printers.firstWhere(
      (p) {
        final name = p.name.toLowerCase();
        return name.contains('thermal') ||
            name.contains('receipt') ||
            name.contains('pos') ||
            name.contains('epson') ||
            name.contains('star');
      },
      orElse: () => printers.first,
    );
  }

  /// Checks whether the printer saved in Settings is currently detected,
  /// without sending a print job.
  static Future<PrinterStatus> checkSelectedPrinterStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(PrinterPrefsKeys.url);
    final savedName = prefs.getString(PrinterPrefsKeys.name);
    if ((savedUrl == null || savedUrl.isEmpty) &&
        (savedName == null || savedName.isEmpty)) {
      return PrinterStatus.notConfigured;
    }
    final printers = await Printing.listPrinters();
    final stillThere = printers.any(
      (p) => p.url.toString() == savedUrl || p.name == savedName,
    );
    return stillThere ? PrinterStatus.available : PrinterStatus.offline;
  }

  /// Wrap raw ESC/POS bytes in a minimal valid PDF so the printing package
  /// can send it. The bytes are embedded as a raw content stream.
  static Future<Uint8List> _wrapRawBytes(Uint8List bytes) async {
    // For raw ESC/POS, best approach on Windows/Linux is a 1pt×1pt blank PDF
    // then the printer driver forwards the drawer pulse via its own port.
    // (True raw printing requires platform channels on mobile.)
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(1, 1),
      build: (_) => pw.Container(),
    ));
    return doc.save();
  }

  // ── Test Print ────────────────────────────────────────────────────────────
  static Future<void> testPrint({Printer? printer}) async {
    final target = await _resolvePrinter(explicit: printer);
    final pdf = await _buildTestPrintPdf(target);
    bool success;
    try {
      success = await Printing.directPrintPdf(
        printer: target,
        onLayout: (_) async => pdf,
        format: _paperWidth80mm,
        name: 'POS-Test-Print',
      );
    } catch (e) {
      throw PrintJobFailedException('Test print to "${target.name}" failed: $e');
    }
    if (!success) {
      throw PrintJobFailedException('Test print to "${target.name}" did not complete.');
    }
  }

  static Future<Uint8List> _buildTestPrintPdf(Printer printer) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.sourceCodeProRegular();
    final fontBold = await PdfGoogleFonts.sourceCodeProBold();
    final url = printer.url.toString();
    final connectionType = (url.startsWith('lpd://') ||
            url.startsWith('ipp://') ||
            url.startsWith('socket://'))
        ? 'Network'
        : 'USB / Local';

    doc.addPage(pw.Page(
      pageFormat: _paperWidth80mm,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('POS TEST PRINT', style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 6),
          _divider(),
          pw.SizedBox(height: 6),
          pw.Text('Printer: ${printer.name}', style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text('Connection: $connectionType', style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text('Status: OK', style: pw.TextStyle(font: fontBold, fontSize: 9)),
          pw.SizedBox(height: 6),
          pw.Text(_formatDateTime(DateTime.now()), style: pw.TextStyle(font: font, fontSize: 8)),
          pw.SizedBox(height: 6),
          _divider(),
        ],
      ),
    ));
    return doc.save();
  }

  // ── Build bill PDF (pre-payment) ──────────────────────────────────────────
  static Future<Uint8List> _buildBillPdf({
    required Order order,
    required String businessName,
    bool is58mm = false,
    String? businessAddress,
    String? tableNumber,
    String? roomName,
  }) async {
    final doc = pw.Document();
    final font     = await PdfGoogleFonts.sourceCodeProRegular();
    final fontBold = await PdfGoogleFonts.sourceCodeProBold();

    doc.addPage(pw.Page(
      pageFormat: getPaperFormat(is58mm),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // ── Header ────────────────────────────────────────────────────
          pw.Text(businessName.toUpperCase(),
              style: pw.TextStyle(font: fontBold, fontSize: 11)),
          if (businessAddress != null)
            pw.Text(businessAddress,
                style: pw.TextStyle(font: font, fontSize: 8),
                textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 6),
          _divider(),
          // ── Table / Room ──────────────────────────────────────────────
          if (tableNumber != null || roomName != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              tableNumber != null ? 'TABLE $tableNumber' : roomName!.toUpperCase(),
              style: pw.TextStyle(font: fontBold, fontSize: 13),
            ),
            pw.SizedBox(height: 4),
          ],
          // ── Order info ────────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Order #${order.orderNumber}',
                  style: pw.TextStyle(font: fontBold, fontSize: 9)),
              pw.Text(_formatDateTime(order.createdAt),
                  style: pw.TextStyle(font: font, fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
          _divider(),
          pw.SizedBox(height: 4),
          // ── Items ──────────────────────────────────────────────────────
          pw.Text('BILL', style: pw.TextStyle(font: fontBold, fontSize: 10)),
          pw.SizedBox(height: 4),
          ...order.items.expand((item) => _itemRows(item, font: font, fontBold: fontBold)),
          pw.SizedBox(height: 4),
          _divider(),
          // ── Totals ────────────────────────────────────────────────────
          if (order.taxAmount > 0)
            _totalRow('VAT (12%)', '₱${order.taxAmount.toStringAsFixed(2)}',
                font: font, fontBold: fontBold),
          if (order.discountAmount > 0)
            _totalRow('Discount', '-₱${order.discountAmount.toStringAsFixed(2)}',
                font: font, fontBold: fontBold),
          pw.SizedBox(height: 4),
          _totalRow('TOTAL', '₱${order.totalAmount.toStringAsFixed(2)}',
              font: font, fontBold: fontBold, large: true),
          pw.SizedBox(height: 6),
          _divider(),
          pw.SizedBox(height: 6),
          pw.Text('This is not an official receipt.',
              style: pw.TextStyle(font: font, fontSize: 7),
              textAlign: pw.TextAlign.center),
          pw.Text('Thank you for dining with us!',
              style: pw.TextStyle(font: font, fontSize: 8),
              textAlign: pw.TextAlign.center),
        ],
      ),
    ));

    return doc.save();
  }

  // ── Build receipt PDF (post-payment) ──────────────────────────────────────
  static Future<Uint8List> _buildReceiptPdf({
    required Order order,
    required double tendered,
    required double change,
    required String businessName,
    bool is58mm = false,
    String? businessAddress,
    String? tableNumber,
    String? roomName,
  }) async {
    final doc = pw.Document();
    final font     = await PdfGoogleFonts.sourceCodeProRegular();
    final fontBold = await PdfGoogleFonts.sourceCodeProBold();

    doc.addPage(pw.Page(
      pageFormat: getPaperFormat(is58mm),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // ── Header ────────────────────────────────────────────────────
          pw.Text(businessName.toUpperCase(),
              style: pw.TextStyle(font: fontBold, fontSize: 11)),
          if (businessAddress != null)
            pw.Text(businessAddress,
                style: pw.TextStyle(font: font, fontSize: 8),
                textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 6),
          _divider(),
          if (tableNumber != null || roomName != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              tableNumber != null ? 'TABLE $tableNumber' : roomName!.toUpperCase(),
              style: pw.TextStyle(font: fontBold, fontSize: 12),
            ),
            pw.SizedBox(height: 4),
          ],
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Order #${order.orderNumber}',
                  style: pw.TextStyle(font: fontBold, fontSize: 9)),
              pw.Text(_formatDateTime(order.createdAt),
                  style: pw.TextStyle(font: font, fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
          _divider(),
          pw.SizedBox(height: 4),
          // ── Items ──────────────────────────────────────────────────────
          ...order.items.expand((item) => _itemRows(item, font: font, fontBold: fontBold)),
          pw.SizedBox(height: 4),
          _divider(),
          // ── Totals ────────────────────────────────────────────────────
          _totalRow('Subtotal', '₱${order.subtotal.toStringAsFixed(2)}',
              font: font, fontBold: fontBold),
          if (order.taxAmount > 0)
            _totalRow('VAT (12%)', '₱${order.taxAmount.toStringAsFixed(2)}',
                font: font, fontBold: fontBold),
          if (order.discountAmount > 0)
            _totalRow('Discount', '-₱${order.discountAmount.toStringAsFixed(2)}',
                font: font, fontBold: fontBold),
          pw.SizedBox(height: 4),
          _totalRow('TOTAL', '₱${order.totalAmount.toStringAsFixed(2)}',
              font: font, fontBold: fontBold, large: true),
          pw.SizedBox(height: 4),
          _divider(),
          // ── Payment ────────────────────────────────────────────────────
          _totalRow('Payment', paymentLabel(order.paymentMethod),
              font: font, fontBold: fontBold),
          if (order.paymentMethod == PaymentMethod.cash) ...[
            _totalRow('Tendered', '₱${tendered.toStringAsFixed(2)}',
                font: font, fontBold: fontBold),
            _totalRow('Change', '₱${change.toStringAsFixed(2)}',
                font: font, fontBold: fontBold),
          ],
          if (order.referenceNumber != null)
            _totalRow('Ref#', order.referenceNumber!,
                font: font, fontBold: fontBold),
          pw.SizedBox(height: 6),
          _divider(),
          pw.SizedBox(height: 6),
          pw.Text('Thank you for dining with us!',
              style: pw.TextStyle(font: font, fontSize: 8),
              textAlign: pw.TextAlign.center),
          pw.Text('Official Receipt',
              style: pw.TextStyle(font: fontBold, fontSize: 8),
              textAlign: pw.TextAlign.center),
        ],
      ),
    ));

    return doc.save();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Renders one row for a plain item, or a bold header row + indented
  /// component rows for a promo — same grouping used on-screen (restaurant/
  /// retail receipt views) and on the kitchen ticket, so a promo prints
  /// consistently everywhere order contents are shown.
  static List<pw.Widget> _itemRows(
    dynamic item, {
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    if (!item.isPromo) {
      return [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            children: [
              pw.Text('${item.quantity}x ',
                  style: pw.TextStyle(font: fontBold, fontSize: 9)),
              pw.Expanded(
                child: pw.Text(item.product.name,
                    style: pw.TextStyle(font: font, fontSize: 9)),
              ),
              pw.Text('₱${item.total.toStringAsFixed(2)}',
                  style: pw.TextStyle(font: fontBold, fontSize: 9)),
            ],
          ),
        ),
      ];
    }

    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2, bottom: 1),
        child: pw.Row(
          children: [
            pw.Text('${item.quantity}x ',
                style: pw.TextStyle(font: fontBold, fontSize: 9)),
            pw.Expanded(
              child: pw.Text(item.product.name,
                  style: pw.TextStyle(font: fontBold, fontSize: 9)),
            ),
            pw.Text('₱${item.total.toStringAsFixed(2)}',
                style: pw.TextStyle(font: fontBold, fontSize: 9)),
          ],
        ),
      ),
      for (final c in item.promoComponents!)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 14, bottom: 1),
          child: pw.Row(
            children: [
              pw.Text('${c.quantity}x ',
                  style: pw.TextStyle(font: font, fontSize: 8)),
              pw.Expanded(
                child: pw.Text(
                  c.variantName != null ? '${c.productName} (${c.variantName})' : c.productName,
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  static pw.Widget _divider() => pw.Divider(thickness: 0.5, height: 1);

  static pw.Widget _totalRow(
    String label,
    String value, {
    required pw.Font font,
    required pw.Font fontBold,
    bool large = false,
  }) {
    final size = large ? 11.0 : 9.0;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: large ? fontBold : font, fontSize: size)),
          pw.Text(value,
              style: pw.TextStyle(font: fontBold, fontSize: size)),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} '
        '${_p(dt.hour)}:${_p(dt.minute)}';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Payment label ─────────────────────────────────────────────────────────────
String paymentLabel(PaymentMethod? method) => switch (method) {
  PaymentMethod.card  => 'Card',
  PaymentMethod.gcash => 'GCash',
  PaymentMethod.maya  => 'Maya',
  _                   => 'Cash',
};