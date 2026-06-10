import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/feature_manager.dart';
import '../../../shared/widgets/app_colors.dart';
import '../dialogs/checkout_dialog.dart';
import '../dialogs/split_bill_dialog.dart';
import '../../../core/models/product.dart';
import '../../../core/services/parked_order_service.dart';
import '../../../features/auth/auth_provider.dart';

class CartPanel extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  const CartPanel({super.key, required this.featureManager});

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final hasKitchen = widget.featureManager.hasFeature('kitchen');
    final total = ref.watch(cartProvider.notifier).grandTotal;

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
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showCustomItemDialog(context),
                  child: Tooltip(
                    message: 'Add custom item',
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha:0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warning.withValues(alpha:0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.edit_outlined, size: 11, color: AppColors.warning),
                          SizedBox(width: 3),
                          Text('Custom', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.warning)),
                        ],
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Barcode scanner ready',
                  child: Icon(Icons.qr_code_scanner_rounded,
                      size: 14,
                      color: AppColors.primary.withValues(alpha:0.5)),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.1),
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
                // ── Right-side actions — icon-only to prevent overflow ──
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Split
                    Tooltip(
                      message: 'Split bill between guests',
                      child: GestureDetector(
                        onTap: items.isEmpty
                            ? null
                            : () => showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => SplitBillDialog(
                                    featureManager: widget.featureManager,
                                  ),
                                ),
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: items.isEmpty
                                ? AppColors.divider.withValues(alpha:0.3)
                                : AppColors.success.withValues(alpha:0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: items.isEmpty
                                    ? AppColors.divider
                                    : AppColors.success.withValues(alpha:0.3)),
                          ),
                          child: Icon(
                            Icons.call_split_outlined,
                            size: 14,
                            color: items.isEmpty
                                ? AppColors.textSecondary.withValues(alpha:0.3)
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ),
                    // Hold
                    Tooltip(
                      message: 'Park / hold this order',
                      child: GestureDetector(
                        onTap: items.isEmpty
                            ? null
                            : () => _showParkDialog(context),
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: items.isEmpty
                                ? AppColors.divider.withValues(alpha:0.3)
                                : AppColors.primary.withValues(alpha:0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: items.isEmpty
                                    ? AppColors.divider
                                    : AppColors.primary.withValues(alpha:0.3)),
                          ),
                          child: Icon(
                            Icons.pause_outlined,
                            size: 14,
                            color: items.isEmpty
                                ? AppColors.textSecondary.withValues(alpha:0.3)
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    // Clear
                    if (items.isNotEmpty)
                      Tooltip(
                        message: 'Clear cart',
                        child: GestureDetector(
                          onTap: cartNotifier.clear,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha:0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.danger.withValues(alpha:0.2)),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ),
                  ],
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
                            color:
                                AppColors.textSecondary.withValues(alpha:0.25)),
                        const SizedBox(height: 10),
                        Text('Cart is empty',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary
                                    .withValues(alpha:0.5))),
                        const SizedBox(height: 6),
                        Text('Scan a barcode to add items',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary
                                    .withValues(alpha:0.35))),
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
                      return GestureDetector(
                        onLongPress: () =>
                            _showNotesDialog(context, item.product.id, item.notes),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              _QuantityStepper(
                                quantity: item.quantity,
                                onDecrement: () => item.quantity == 1
                                    ? cartNotifier
                                        .removeProduct(item.product.id)
                                    : cartNotifier
                                        .decrementProduct(item.product.id),
                                onIncrement: () =>
                                    cartNotifier.addProduct(item.product, variant: item.selectedVariant),
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
                                    if (item.notes != null &&
                                        item.notes!.isNotEmpty)
                                      Text(item.notes!,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.warning,
                                              fontStyle: FontStyle.italic),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)
                                    else
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
                // REPLACE
                Row(
                  children: [
                    const Text('Subtotal',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(
                      '₱${ref.watch(cartProvider.notifier).itemsTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary),
                    ),
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
                                featureManager: widget.featureManager,
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
              ? AppColors.primary.withValues(alpha:0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon,
            size: 13,
            color:
                positive ? AppColors.primary : AppColors.textSecondary),
      ),
    );
  }
}

// ── Custom item dialog (lives on _CartPanelState) ─────────────────────────────

extension _CartPanelDialogs on _CartPanelState {
  void _showParkDialog(BuildContext context) {
    final labelController = TextEditingController();
    final items = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hold Order',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${items.fold(0, (s, i) => s + i.quantity)} item(s) · ₱${cartNotifier.grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. Table 3, John, To-go'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.pause_outlined, size: 16),
            label: const Text('Hold'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(ctx);
              // Get businessId from profile
              final profile = ref
                  .read(profileProvider)
                  .asData
                  ?.value;
              if (profile?.businessId == null) return;

              await ref.read(parkedOrderProvider.notifier).parkCart(
                    businessId: profile!.businessId!,
                    label: labelController.text,
                    items: items,
                    orderDiscountAmount: cartNotifier.orderDiscountAmount,
                    orderDiscountType: cartNotifier.orderDiscountType,
                    tipAmount: cartNotifier.tipAmount,
                  );
              cartNotifier.clear();
            },
          ),
        ],
      ),
    );
  }

  void _showNotesDialog(BuildContext context, String productId, String? existing) {
    final controller = TextEditingController(text: existing ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Item Note',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 120,
          decoration: const InputDecoration(
            hintText: 'e.g. no onions, extra sauce, well done…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (existing != null && existing.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(cartProvider.notifier).setItemNotes(productId, null);
                Navigator.pop(ctx);
              },
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.danger)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(cartProvider.notifier)
                  .setItemNotes(productId, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCustomItemDialog(BuildContext context) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Item name', hintText: 'e.g. Special Request'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price', prefixText: '₱'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) return 'Invalid price';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final product = Product.custom(
                name: nameController.text.trim(),
                price: double.parse(priceController.text.trim()),
              );
              ref.read(cartProvider.notifier).addProduct(product);
              Navigator.pop(ctx);
            },
            child: const Text('Add to Cart'),
          ),
        ],
      ),
    );
  }
}
