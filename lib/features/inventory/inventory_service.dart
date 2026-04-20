// lib/features/inventory/inventory_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/product.dart';

class InventoryEntry {
  final Product product;
  final int stock;
  final int lowStockThreshold;

  InventoryEntry({
    required this.product,
    required this.stock,
    this.lowStockThreshold = 5,
  });

  bool get isLowStock => stock <= lowStockThreshold;

  InventoryEntry copyWith({int? stock}) {
    return InventoryEntry(
      product: product,
      stock: stock ?? this.stock,
      lowStockThreshold: lowStockThreshold,
    );
  }
}

class InventoryNotifier extends StateNotifier<List<InventoryEntry>> {
  InventoryNotifier() : super(_seedData());

  static List<InventoryEntry> _seedData() => [
        InventoryEntry(product: Product(id: '1', name: 'Burger', price: 120, category: 'Food'), stock: 30),
        InventoryEntry(product: Product(id: '2', name: 'Fries', price: 60, category: 'Food'), stock: 50),
        InventoryEntry(product: Product(id: '3', name: 'Coke', price: 45, category: 'Drinks'), stock: 4),
        InventoryEntry(product: Product(id: '5', name: 'T-Shirt (S)', price: 250, barcode: '1234567890', category: 'Apparel'), stock: 12),
        InventoryEntry(product: Product(id: '6', name: 'T-Shirt (M)', price: 250, barcode: '1234567891', category: 'Apparel'), stock: 2),
      ];

  void adjustStock(String productId, int delta) {
    state = [
      for (final entry in state)
        if (entry.product.id == productId)
          entry.copyWith(stock: (entry.stock + delta).clamp(0, 9999))
        else
          entry,
    ];
  }

  void setStock(String productId, int value) {
    state = [
      for (final entry in state)
        if (entry.product.id == productId)
          entry.copyWith(stock: value.clamp(0, 9999))
        else
          entry,
    ];
  }

  List<InventoryEntry> get lowStockItems =>
      state.where((e) => e.isLowStock).toList();
}

final inventoryProvider =
    StateNotifierProvider<InventoryNotifier, List<InventoryEntry>>(
        (ref) => InventoryNotifier());