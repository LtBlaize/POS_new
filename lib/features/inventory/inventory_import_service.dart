// lib/features/inventory/inventory_import_service.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/product.dart';
import '../../features/auth/auth_provider.dart';

// ── Result types ──────────────────────────────────────────────────────────────

class ImportRow {
  final int rowNumber;
  final String name;
  final double price;
  final double costPrice;
  final int stockQuantity;
  final bool trackInventory;
  final String? category;
  final String? barcode;
  final String? sku;
  final String? description;
  final bool sendToKitchen;

  // Resolved after category lookup
  String? categoryId;

  // Set during preview — matches existing product by name+barcode
  Product? existingProduct;
  bool get isUpdate => existingProduct != null;

  ImportRow({
    required this.rowNumber,
    required this.name,
    required this.price,
    required this.costPrice,
    required this.stockQuantity,
    required this.trackInventory,
    this.category,
    this.barcode,
    this.sku,
    this.description,
    this.sendToKitchen = true,
    this.categoryId,
    this.existingProduct,
  });
}

class ImportRowError {
  final int rowNumber;
  final String message;
  const ImportRowError(this.rowNumber, this.message);
}

class ImportPreview {
  final List<ImportRow> valid;
  final List<ImportRowError> errors;
  final int newCount;
  final int updateCount;

  const ImportPreview({
    required this.valid,
    required this.errors,
    required this.newCount,
    required this.updateCount,
  });
}

class ImportResult {
  final int inserted;
  final int updated;
  final String? error;
  const ImportResult({this.inserted = 0, this.updated = 0, this.error});
  bool get success => error == null;
}

// ── Expected columns ──────────────────────────────────────────────────────────

// Required: name, price
// Optional: cost_price, stock_quantity, track_inventory, category,
//           barcode, sku, description, send_to_kitchen
const _kRequiredColumns = ['name', 'price'];

// ── Service ───────────────────────────────────────────────────────────────────

final importServiceProvider = Provider<InventoryImportService>((ref) {
  return InventoryImportService(
    client: ref.read(supabaseClientProvider),
    ref: ref,
  );
});

class InventoryImportService {
  final SupabaseClient _client;
  final Ref _ref;

  InventoryImportService({required SupabaseClient client, required Ref ref})
      : _client = client,
        _ref = ref;

  // ── Pick and parse CSV ────────────────────────────────────────────────────

  /// Returns null if user cancelled.
  Future<ImportPreview?> pickAndPreview() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    String csvText;

    if (kIsWeb) {
      csvText = String.fromCharCodes(file.bytes!);
    } else {
      csvText = await File(file.path!).readAsString();
    }

    return _buildPreview(csvText);
  }

  Future<ImportPreview> _buildPreview(String csvText) async {
    final profile = _ref.read(profileProvider).asData?.value;
    final businessId = profile?.businessId ?? '';

    final lines = _splitLines(csvText);
    if (lines.isEmpty) {
      return const ImportPreview(valid: [], errors: [
        ImportRowError(0, 'File is empty')
      ], newCount: 0, updateCount: 0);
    }

    // Parse header
    final headers = _parseCsvLine(lines.first)
        .map((h) => h.trim().toLowerCase().replaceAll(' ', '_'))
        .toList();

    // Validate required columns
    final missingCols = _kRequiredColumns
        .where((c) => !headers.contains(c))
        .toList();
    if (missingCols.isNotEmpty) {
      return ImportPreview(
        valid: [],
        errors: [ImportRowError(0, 'Missing required columns: ${missingCols.join(', ')}')],
        newCount: 0,
        updateCount: 0,
      );
    }

    // Fetch existing products and categories once
    final existingProducts = await _client
        .from('products')
        .select('id, name, barcode')
        .eq('business_id', businessId)
        .eq('is_active', true);

    final existingByName = <String, Map<String, dynamic>>{};
    final existingByBarcode = <String, Map<String, dynamic>>{};
    for (final p in existingProducts as List) {
      existingByName[(p['name'] as String).toLowerCase()] = p;
      if (p['barcode'] != null) {
        existingByBarcode[p['barcode'] as String] = p;
      }
    }

    // Fetch + cache categories
    final categoryRows = await _client
        .from('categories')
        .select('id, name')
        .eq('business_id', businessId)
        .eq('is_active', true);

    final categoryByName = <String, String>{};
    for (final c in categoryRows as List) {
      categoryByName[(c['name'] as String).toLowerCase()] = c['id'] as String;
    }

    final valid = <ImportRow>[];
    final errors = <ImportRowError>[];

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final rowNum = i + 1;

      try {
        final cols = _parseCsvLine(line);
        final row = _toMap(headers, cols);

        // ── Validate required fields ──────────────────────────────────
        final name = (row['name'] ?? '').trim();
        if (name.isEmpty) {
          errors.add(ImportRowError(rowNum, 'Name is empty'));
          continue;
        }

        final priceStr = (row['price'] ?? '').trim();
        final price = double.tryParse(priceStr);
        if (price == null || price < 0) {
          errors.add(ImportRowError(rowNum, '"$name": invalid price "$priceStr"'));
          continue;
        }

        // ── Optional fields ──────────────────────────────────────────
        final costPrice = double.tryParse(row['cost_price'] ?? '') ?? 0;
        final stockQuantity = int.tryParse(row['stock_quantity'] ?? '') ?? 0;
        final trackInventory = _parseBool(row['track_inventory'], defaultValue: stockQuantity > 0);
        final sendToKitchen = _parseBool(row['send_to_kitchen'], defaultValue: true);
        final barcode = _nullIfEmpty(row['barcode']);
        final sku = _nullIfEmpty(row['sku']);
        final description = _nullIfEmpty(row['description']);
        final categoryName = _nullIfEmpty(row['category']);

        // Resolve category
        String? categoryId;
        if (categoryName != null) {
          categoryId = categoryByName[categoryName.toLowerCase()];
          // Unknown categories are not errors — they'll be created on commit
        }

        // Match existing product (barcode takes priority, then name)
        Product? existingProduct;
        Map<String, dynamic>? existing;
        if (barcode != null && existingByBarcode.containsKey(barcode)) {
          existing = existingByBarcode[barcode];
        } else {
          existing = existingByName[name.toLowerCase()];
        }
        if (existing != null) {
          existingProduct = Product(
            id: existing['id'] as String,
            businessId: businessId,
            name: existing['name'] as String,
            price: price,
          );
        }

        valid.add(ImportRow(
          rowNumber: rowNum,
          name: name,
          price: price,
          costPrice: costPrice,
          stockQuantity: stockQuantity,
          trackInventory: trackInventory,
          category: categoryName,
          categoryId: categoryId,
          barcode: barcode,
          sku: sku,
          description: description,
          sendToKitchen: sendToKitchen,
          existingProduct: existingProduct,
        ));
      } catch (e) {
        errors.add(ImportRowError(rowNum, 'Parse error: $e'));
      }
    }

    final updateCount = valid.where((r) => r.isUpdate).length;
    final newCount = valid.length - updateCount;

    return ImportPreview(
      valid: valid,
      errors: errors,
      newCount: newCount,
      updateCount: updateCount,
    );
  }

  // ── Commit import ─────────────────────────────────────────────────────────

  Future<ImportResult> commit(ImportPreview preview) async {
    final profile = _ref.read(profileProvider).asData?.value;
    final businessId = profile?.businessId ?? '';
    if (businessId.isEmpty) {
      return const ImportResult(error: 'No business profile found.');
    }

    int inserted = 0;
    int updated = 0;

    try {
      // Create missing categories first
      final unknownCategories = preview.valid
          .where((r) => r.category != null && r.categoryId == null)
          .map((r) => r.category!)
          .toSet();

      final createdCategories = <String, String>{};
      for (final catName in unknownCategories) {
        try {
          final row = await _client
              .from('categories')
              .insert({
                'business_id': businessId,
                'name': catName,
                'is_active': true,
              })
              .select('id')
              .single();
          createdCategories[catName.toLowerCase()] = row['id'] as String;
        } catch (e) {
          // Category may have been created by a parallel request — fetch it
          final existing = await _client
              .from('categories')
              .select('id')
              .eq('business_id', businessId)
              .eq('name', catName)
              .maybeSingle();
          if (existing != null) {
            createdCategories[catName.toLowerCase()] = existing['id'] as String;
          }
        }
      }

      // Resolve category IDs for rows that had unknown categories
      for (final row in preview.valid) {
        if (row.category != null && row.categoryId == null) {
          row.categoryId = createdCategories[row.category!.toLowerCase()];
        }
      }

      // Split into inserts and updates
      final toInsert = preview.valid.where((r) => !r.isUpdate).toList();
      final toUpdate = preview.valid.where((r) => r.isUpdate).toList();

      // Batch insert new products (chunks of 50)
      for (int i = 0; i < toInsert.length; i += 50) {
        final chunk = toInsert.sublist(i, (i + 50).clamp(0, toInsert.length));
        await _client.from('products').insert(
          chunk.map((r) => _toInsertPayload(r, businessId)).toList(),
        );
        inserted += chunk.length;
      }

      // Update existing products one by one (Supabase batch update not supported)
      for (final r in toUpdate) {
        await _client
            .from('products')
            .update(_toUpdatePayload(r))
            .eq('id', r.existingProduct!.id);
        updated++;
      }

      debugPrint('[Import] Done: $inserted inserted, $updated updated');
      return ImportResult(inserted: inserted, updated: updated);
    } catch (e, stack) {
      debugPrint('[Import] Commit failed: $e\n$stack');
      return ImportResult(error: e.toString());
    }
  }

  // ── Payload builders ──────────────────────────────────────────────────────

  Map<String, dynamic> _toInsertPayload(ImportRow r, String businessId) => {
        'business_id': businessId,
        'name': r.name,
        'price': r.price,
        'cost_price': r.costPrice,
        'description': r.description,
        'barcode': r.barcode,
        'sku': r.sku,
        'category_id': r.categoryId,
        'track_inventory': r.trackInventory,
        'stock_quantity': r.stockQuantity,
        'send_to_kitchen': r.sendToKitchen,
        'is_available': r.stockQuantity > 0 || !r.trackInventory,
        'is_active': true,
      };

  Map<String, dynamic> _toUpdatePayload(ImportRow r) => {
        'name': r.name,
        'price': r.price,
        'cost_price': r.costPrice,
        if (r.description != null) 'description': r.description,
        if (r.barcode != null) 'barcode': r.barcode,
        if (r.sku != null) 'sku': r.sku,
        if (r.categoryId != null) 'category_id': r.categoryId,
        'track_inventory': r.trackInventory,
        'stock_quantity': r.stockQuantity,
        'send_to_kitchen': r.sendToKitchen,
        'is_available': r.stockQuantity > 0 || !r.trackInventory,
        'updated_at': DateTime.now().toIso8601String(),
      };

  // ── CSV parsing ───────────────────────────────────────────────────────────

  List<String> _splitLines(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
  }

  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    fields.add(buffer.toString());
    return fields;
  }

  Map<String, String> _toMap(List<String> headers, List<String> cols) {
    final map = <String, String>{};
    for (int i = 0; i < headers.length; i++) {
      map[headers[i]] = i < cols.length ? cols[i].trim() : '';
    }
    return map;
  }

  bool _parseBool(String? value, {required bool defaultValue}) {
    if (value == null || value.isEmpty) return defaultValue;
    final v = value.toLowerCase().trim();
    if (v == 'true' || v == 'yes' || v == '1') return true;
    if (v == 'false' || v == 'no' || v == '0') return false;
    return defaultValue;
  }

  String? _nullIfEmpty(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}