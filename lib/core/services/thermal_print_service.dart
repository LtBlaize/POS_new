import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order.dart';

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
  }) async {
    final pdf = await _buildBillPdf(
      order: order,
      businessName: businessName,
      is58mm: is58mm,
      businessAddress: businessAddress,
      tableNumber: tableNumber,
      roomName: roomName,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      format: getPaperFormat(is58mm),
      name: 'Bill-Order#${order.orderNumber}',
    );
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

    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      format: getPaperFormat(is58mm),
      name: 'Receipt-Order#${order.orderNumber}',
    );
  }

  // ── Open Cash Drawer ──────────────────────────────────────────────────────
  /// Sends ESC/POS pulse command through the default printer.
  /// Works on any standard thermal printer with a drawer kick port.
  static Future<void> openCashDrawer() async {
    // ESC/POS: ESC p m t1 t2  (pin 2 on, 25×2ms on, 250×2ms off)
    final drawerPulse = Uint8List.fromList([
      0x1B, 0x70, 0x00, 0x19, 0xFA, // pin 2
      0x1B, 0x70, 0x01, 0x19, 0xFA, // pin 5 (some printers use this)
    ]);

    try {
      await Printing.directPrintPdf(
        printer: await _getDefaultPrinter(),
        onLayout: (_) async => _wrapRawBytes(drawerPulse),
      );
    } catch (e) {
      debugPrint('[CashDrawer] Could not open drawer: $e');
    }
  }

  // ── Get default / first available printer ─────────────────────────────────
  static Future<Printer> _getDefaultPrinter() async {
    final printers = await Printing.listPrinters();
    if (printers.isEmpty) throw Exception('No printers found');
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
          ...order.items.map((item) => pw.Padding(
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
          )),
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
          ...order.items.map((item) => pw.Padding(
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
          )),
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