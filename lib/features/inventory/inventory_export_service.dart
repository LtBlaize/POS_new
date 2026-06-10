// lib/features/inventory/inventory_export_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'inventory_service.dart';

final exportServiceProvider = Provider<InventoryExportService>((ref) {
  return InventoryExportService(ref);
});

class InventoryExportService {
  final Ref _ref;
  InventoryExportService(this._ref);

  Future<void> exportToCsv() async {
    final entries = _ref.read(inventoryProvider).entries;

    final buffer = StringBuffer();

    // Header row — matches import column names exactly
    buffer.writeln(
      'name,price,cost_price,stock_quantity,track_inventory,'
      'category,barcode,sku,description,send_to_kitchen',
    );

    for (final entry in entries) {
      final p = entry.product;
      buffer.writeln([
        _escape(p.name),
        p.price.toStringAsFixed(2),
        p.costPrice.toStringAsFixed(2),
        p.stockQuantity,
        p.trackInventory ? 'true' : 'false',
        _escape(p.category),
        _escape(p.barcode ?? ''),
        _escape(p.sku ?? ''),
        _escape(p.description ?? ''),
        p.sendToKitchen ? 'true' : 'false',
      ].join(','));
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final fileName =
        'inventory_${DateTime.now().toIso8601String().substring(0, 10)}';

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
    } else if (Platform.isAndroid || Platform.isIOS) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
    } else {
      // Desktop — save to downloads folder
      final dir = Platform.isWindows
          ? '${Platform.environment['USERPROFILE']}\\Downloads'
          : '${Platform.environment['HOME']}/Downloads';
      final file = File('$dir/$fileName.csv');
      await file.writeAsBytes(bytes);
    }
  }

  String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}