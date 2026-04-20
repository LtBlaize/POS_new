// lib/features/pos/widgets/product_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/product.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../shared/widgets/app_colors.dart';

// Category → gradient mapping
const _categoryGradients = <String, List<Color>>{
  'Food': [Color(0xFFFF9966), Color(0xFFFF5E62)],
  'Drinks': [Color(0xFF43C6AC), Color(0xFF191654)],
  'Apparel': [Color(0xFF667EEA), Color(0xFF764BA2)],
  'Stationery': [Color(0xFFF7971E), Color(0xFFFFD200)],
  'Electronics': [Color(0xFF2193B0), Color(0xFF6DD5ED)],
  'Desserts': [Color(0xFFDA4453), Color(0xFF89216B)],
};

List<Color> _gradientFor(String category) =>
    _categoryGradients[category] ??
    [AppColors.primary, const Color(0xFF1A4A8A)];

class ProductCard extends ConsumerStatefulWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scaleAnim = Tween(begin: 1.0, end: 0.93).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() async {
    HapticFeedback.lightImpact();
    await _controller.forward();
    await _controller.reverse();

    ref.read(cartProvider.notifier).addProduct(widget.product);

    setState(() => _added = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _added = false);
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final inCart = cartItems
        .where((i) => i.product.id == widget.product.id)
        .fold(0, (sum, i) => sum + i.quantity);
    final gradColors = _gradientFor(widget.product.category);

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: inCart > 0
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.divider,
              width: inCart > 0 ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Color band top
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(13)),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _added
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 32, key: ValueKey('check'))
                              : Text(
                                  widget.product.name[0],
                                  key: const ValueKey('letter'),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white.withOpacity(0.4),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    // Cart quantity pill
                    if (inCart > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4)
                            ],
                          ),
                          child: Text(
                            '×$inCart',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: gradColors.first,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Info section
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '₱${widget.product.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: gradColors.first,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: gradColors.first.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 14,
                              color: gradColors.first,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}