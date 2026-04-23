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
            // Each card should be at least 130px wide
            final crossAxisCount = (constraints.maxWidth / 130).floor().clamp(2, 6);
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.95,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: products.length,
              itemBuilder: (_, index) => ProductCard(product: products[index]),
            );
          },
        );
      },
    );
  }
}