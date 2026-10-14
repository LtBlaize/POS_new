// lib/core/services/thermal_print_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';
import 'escpos_receipts.dart';
import 'thermal_transport.dart';

class PrinterNotFoundException implements Exception {
  final String message;
  PrinterNotFoundException(this.message);
  @override
  String toString() => message;
}

class PrinterOfflineException implements Exception {
  final String message;
  PrinterOfflineException(this.message);
  @override
  String toString() => message;
}

class PrintJobFailedException implements Exception {
  final String message;
  PrintJobFailedException(this.message);
  @override
  String toString() => message;
}

enum PrinterStatus { notConfigured, offline, available }

class ThermalPrintService {
  static Future<void> _send(Uint8List bytes, String what) async {
    try {
      await ThermalTransport.send(bytes);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      throw PrintJobFailedException('Failed to print $what: $msg');
    }
  }

  // `printer` is accepted but ignored so existing callers still compile.
  static Future<void> printBill({
    required Order order,
    required String businessName,
    bool is58mm = true,
    String? businessAddress,
    String? tableNumber,
    String? roomName,
    Object? printer,
  }) async {
    final bytes = await EscPosReceipts.receipt(
      order: order,
      businessName: businessName,
      businessAddress: businessAddress,
      tableNumber: tableNumber ?? roomName,
      isBill: true,
    );
    await _send(bytes, 'bill');
  }

  static Future<void> printReceipt({
    required Order order,
    required double tendered,
    required double change,
    required String businessName,
    bool is58mm = true,
    String? businessAddress,
    String? tableNumber,
    String? roomName,
    Object? printer,
  }) async {
    final bytes = await EscPosReceipts.receipt(
      order: order,
      businessName: businessName,
      businessAddress: businessAddress,
      tableNumber: tableNumber ?? roomName,
      tendered: tendered,
      change: change,
    );
    await _send(bytes, 'receipt');
  }

  /// Never throws: a failed drawer kick must not block checkout.
  static Future<bool> openCashDrawer({Object? printer}) async {
    try {
      await ThermalTransport.send(await EscPosReceipts.drawerKick());
      return true;
    } catch (e) {
      debugPrint('[CashDrawer] Could not open drawer: $e');
      return false;
    }
  }

  static Future<void> testPrint({Object? printer}) async {
    await _send(await EscPosReceipts.testPage(), 'test page');
  }

  static Future<PrinterStatus> checkSelectedPrinterStatus() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(PrinterPrefs2.id);
    if (id == null || id.isEmpty) return PrinterStatus.notConfigured;
    final devices = await ThermalTransport.listDevices();
    return devices.any((d) => d.id == id)
        ? PrinterStatus.available
        : PrinterStatus.offline;
  }
}

String paymentLabel(PaymentMethod? method) => switch (method) {
  PaymentMethod.card => 'Card',
  PaymentMethod.gcash => 'GCash',
  PaymentMethod.maya => 'Maya',
  _ => 'Cash',
};
