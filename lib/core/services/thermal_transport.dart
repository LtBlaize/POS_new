// lib/core/services/thermal_transport.dart
//
// Sends raw ESC/POS bytes to a thermal printer on any platform.
//   Windows -> RAW job to a printer installed in Windows (win32 / winspool)
//   Android -> Bluetooth Classic (print_bluetooth_thermal)
//
// pubspec additions:
//   print_bluetooth_thermal: ^1.1.4
//   win32: ^5.5.0
//   ffi: ^2.1.0
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart'; // optional, see notes
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';

class PrinterDevice {
  final String name;
  final String id; // Windows: printer name | Android: Bluetooth MAC
  final String kind; // 'system' or 'bluetooth'
  const PrinterDevice(this.name, this.id, this.kind);
}

class PrinterPrefs2 {
  static const kind = 'printer_kind'; // 'system' | 'bluetooth'
  static const id = 'printer_id';
  static const name = 'printer_name';
}

class ThermalTransport {
  static bool get _isWindows => !kIsWeb && Platform.isWindows;
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // ── Discovery ────────────────────────────────────────────────────────────
  static Future<List<PrinterDevice>> listDevices() async {
    if (_isWindows) {
      final printers = await Printing.listPrinters();
      return printers
          .map((p) => PrinterDevice(p.name, p.name, 'system'))
          .toList();
    }
    if (_isAndroid) {
      await _ensureBluetoothPermissions();
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      return paired
          .map((b) => PrinterDevice(b.name, b.macAdress, 'bluetooth'))
          .toList();
    }
    return [];
  }

  static Future<void> saveSelection(PrinterDevice d) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(PrinterPrefs2.kind, d.kind);
    await p.setString(PrinterPrefs2.id, d.id);
    await p.setString(PrinterPrefs2.name, d.name);
  }

  // ── Send ─────────────────────────────────────────────────────────────────
  /// Throws a String-message Exception on failure.
  static Future<void> send(Uint8List bytes) async {
    final p = await SharedPreferences.getInstance();
    final kind = p.getString(PrinterPrefs2.kind);
    final id = p.getString(PrinterPrefs2.id);
    if (kind == null || id == null) {
      throw Exception('No printer selected. Pick one in Settings > Printer.');
    }
    if (kind == 'system') {
      if (!_isWindows) throw Exception('System printers are only supported on Windows.');
      _sendWindowsRaw(id, bytes);
    } else {
      await _sendBluetooth(id, bytes);
    }
  }

  // ── Android Bluetooth ────────────────────────────────────────────────────
  static Future<void> _ensureBluetoothPermissions() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    }
  }

  static Future<void> _sendBluetooth(String mac, Uint8List bytes) async {
    await _ensureBluetoothPermissions();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw Exception('Bluetooth is off. Turn it on and try again.');
    }
    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!ok) {
        throw Exception('Could not connect to the printer. Is it on and paired?');
      }
    }
    final ok = await PrintBluetoothThermal.writeBytes(bytes.toList());
    if (!ok) throw Exception('Printer connected but the write failed.');
  }

  // ── Windows RAW spooler ──────────────────────────────────────────────────
  static void _sendWindowsRaw(String printerName, Uint8List bytes) {
    final hPrinter = calloc<HANDLE>();
    final docInfo = calloc<DOC_INFO_1>();
    final namePtr = printerName.toNativeUtf16();
    final docName = 'FluxPoint'.toNativeUtf16();
    final dataType = 'RAW'.toNativeUtf16();
    final buf = calloc<Uint8>(bytes.length);
    final written = calloc<DWORD>();
    var opened = false;

    try {
      if (OpenPrinter(namePtr, hPrinter, nullptr) == 0) {
        throw Exception('Windows cannot open printer "$printerName".');
      }
      opened = true;

      docInfo.ref
        ..pDocName = docName
        ..pOutputFile = nullptr
        ..pDatatype = dataType;

      if (StartDocPrinter(hPrinter.value, 1, docInfo) == 0) {
        throw Exception('StartDocPrinter failed.');
      }
      StartPagePrinter(hPrinter.value);

      buf.asTypedList(bytes.length).setAll(0, bytes);
      final ok = WritePrinter(hPrinter.value, buf, bytes.length, written);

      EndPagePrinter(hPrinter.value);
      EndDocPrinter(hPrinter.value);

      if (ok == 0 || written.value != bytes.length) {
        throw Exception('Printer did not accept all data.');
      }
    } finally {
      if (opened) ClosePrinter(hPrinter.value);
      free(hPrinter);
      free(docInfo);
      free(namePtr);
      free(docName);
      free(dataType);
      free(buf);
      free(written);
    }
  }
}