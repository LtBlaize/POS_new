// lib/features/pos/widgets/product_grid.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/product_provider.dart';
import 'product_card.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productListProvider);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (_) {
        final products = ref.watch(filteredProductsProvider);
        if (products.isEmpty) {
          return const Center(
            child: Text('No products in this category.',
                style: TextStyle(color: Colors.grey)),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount =
                (constraints.maxWidth / 130).floor().clamp(2, 6);
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.95,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: products.length,
              // ✅ KEY FIX: ValueKey ensures Flutter maps each card widget
              // to the correct product when the list changes order or length.
              // Without this, Flutter reuses card state by position (index),
              // so tapping card at index 0 uses the state of whatever was
              // previously at index 0 — causing wrong product to be added.
              itemBuilder: (_, index) => ProductCard(
                key: ValueKey(products[index].id),
                product: products[index],
              ),
            );
          },
        );
      },
    );
  }
}