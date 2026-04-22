import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/feature_manager.dart';
import '../../../shared/widgets/app_colors.dart';
import '../dialogs/checkout_dialog.dart';

class CartPanel extends ConsumerWidget {
  final FeatureManager featureManager;
  const CartPanel({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final hasKitchen = featureManager.hasFeature('kitchen');
    final total = items.fold(0.0, (sum, i) => sum + i.total);

    return Container(
      width: 340,
      color: Colors.white,
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                const Text('Cart',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${items.fold(0, (s, i) => s + i.quantity)}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                  ),
                ],
                const Spacer(),
                if (items.isNotEmpty)
                  TextButton.icon(
                    onPressed: cartNotifier.clear,
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: AppColors.danger),
                    label: const Text('Clear',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.danger)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)),
                  ),
              ],
            ),
          ),

          // ── Items list ────────────────────────────────────────
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 40,
                            color: AppColors.textSecondary.withOpacity(0.25)),
                        const SizedBox(height: 10),
                        Text('Cart is empty',
                            style: TextStyle(
                                fontSize: 13,
                                color:
                                    AppColors.textSecondary.withOpacity(0.5))),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            _QuantityStepper(
                              quantity: item.quantity,
                              onDecrement: () => item.quantity == 1
                                  ? cartNotifier.removeProduct(item.product.id)
                                  : cartNotifier.decrementProduct(
                                      item.product.id),
                              onIncrement: () =>
                                  cartNotifier.addProduct(item.product),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                      '₱${item.product.price.toStringAsFixed(0)} each',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Text('₱${item.total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // ── Footer ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Subtotal',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const Spacer(),
                    Text('₱${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    Text('₱${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () => showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => CheckoutDialog(
                                featureManager: featureManager,
                              ),
                            ),
                    icon: Icon(
                      hasKitchen
                          ? Icons.kitchen_outlined
                          : Icons.point_of_sale_outlined,
                      size: 18,
                    ),
                    label: Text(
                      hasKitchen ? 'Send to Kitchen' : 'Pay',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          hasKitchen ? AppColors.warning : AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.divider,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quantity stepper ──────────────────────────────────────────────────────────

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(icon: Icons.remove, onTap: onDecrement),
        SizedBox(
          width: 24,
          child: Text('$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        _StepBtn(icon: Icons.add, onTap: onIncrement, positive: true),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool positive;

  const _StepBtn(
      {required this.icon, required this.onTap, this.positive = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: positive
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon,
            size: 13,
            color: positive ? AppColors.primary : AppColors.textSecondary),
      ),
    );
  }
}