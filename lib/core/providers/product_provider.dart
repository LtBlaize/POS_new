// lib/core/providers/product_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

// Simulated product list — replace with DB/API source later
final productListProvider = Provider<List<Product>>((ref) {
  return [
    Product(id: '1', name: 'Burger', price: 120, category: 'Food'),
    Product(id: '2', name: 'Fries', price: 60, category: 'Food'),
    Product(id: '3', name: 'Coke', price: 45, category: 'Drinks'),
    Product(id: '4', name: 'Water', price: 25, category: 'Drinks'),
    Product(id: '5', name: 'T-Shirt (S)', price: 250, barcode: '1234567890', category: 'Apparel'),
    Product(id: '6', name: 'T-Shirt (M)', price: 250, barcode: '1234567891', category: 'Apparel'),
    Product(id: '7', name: 'Cap', price: 180, barcode: '9876543210', category: 'Apparel'),
    Product(id: '8', name: 'Notebook', price: 75, barcode: '1111111111', category: 'Stationery'),
  ];
});

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productListProvider);
  final category = ref.watch(selectedCategoryProvider);
  if (category == null) return products;
  return products.where((p) => p.category == category).toList();
});

final categoryListProvider = Provider<List<String>>((ref) {
  final products = ref.watch(productListProvider);
  return products.map((p) => p.category).toSet().toList();
});