import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/order.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/providers/order_provider.dart';
import '../../../core/services/feature_manager.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../shared/widgets/app_colors.dart';

// Tracks which payment method is selected in the dialog
final _selectedPaymentProvider =
    StateProvider.autoDispose<PaymentMethod>((ref) => PaymentMethod.cash);

class CheckoutDialog extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  const CheckoutDialog({super.key, required this.featureManager});

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  final _tenderedController = TextEditingController();
  bool _placing = false;
  Order? _completedOrder; // set after successful placeOrder

  @override
  void dispose() {
    _tenderedController.dispose();
    super.dispose();
  }

  double get _subtotal {
    final items = ref.read(cartProvider);
    return items.fold(0.0, (s, i) => s + i.total);
  }

  double get _tendered =>
      double.tryParse(_tenderedController.text.replaceAll(',', '')) ?? 0;

  double get _change => (_tendered - _subtotal).clamp(0, double.infinity);

  bool get _canConfirm {
    final method = ref.read(_selectedPaymentProvider);
    if (method == PaymentMethod.cash) return _tendered >= _subtotal;
    return true; // card / gcash / maya — no tendered amount required
  }

  Future<void> _confirm() async {
    if (!_canConfirm || _placing) return;

    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    final profile = ref.read(profileProvider).asData?.value;
    if (profile?.businessId == null) {
      _showError('No business profile found. Please log in again.');
      return;
    }

    final method = ref.read(_selectedPaymentProvider);
    final service = ref.read(orderServiceProvider);

    setState(() => _placing = true);

    try {
      // 1. Place the order (inserts orders + order_items rows)
      final order = await service.placeOrder(
        businessId: profile!.businessId!,
        items: items,
        notes: null,
      );

      // 2. Record payment
      await service.processPayment(
        orderId: order.id,
        method: method,
        amountTendered: method == PaymentMethod.cash ? _tendered : _subtotal,
        changeAmount: method == PaymentMethod.cash ? _change : 0,
      );

      // 3. If kitchen feature enabled, send to kitchen display
      if (widget.featureManager.hasFeature('kitchen')) {
        await ref
            .read(supabaseClientProvider)
            .from('kitchen_tickets')
            .insert({
          'order_id': order.id,
          'business_id': profile.businessId,
          'status': 'queued',
        });
      }

      // 4. Clear cart and show receipt
      ref.read(cartProvider.notifier).clear();
      setState(() {
        _completedOrder = order;
        _placing = false;
      });
    } catch (e) {
      setState(() => _placing = false);
      _showError('Failed to place order: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show receipt screen after successful order
    if (_completedOrder != null) {
      return _ReceiptView(
        order: _completedOrder!,
        tendered: _tendered,
        change: _change,
        onDone: () => Navigator.of(context).pop(),
      );
    }

    return _CheckoutView(
      featureManager: widget.featureManager,
      tenderedController: _tenderedController,
      subtotal: _subtotal,
      tendered: _tendered,
      change: _change,
      canConfirm: _canConfirm,
      placing: _placing,
      onConfirm: _confirm,
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}

// ── Checkout form ─────────────────────────────────────────────────────────────

class _CheckoutView extends ConsumerWidget {
  final FeatureManager featureManager;
  final TextEditingController tenderedController;
  final double subtotal;
  final double tendered;
  final double change;
  final bool canConfirm;
  final bool placing;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _CheckoutView({
    required this.featureManager,
    required this.tenderedController,
    required this.subtotal,
    required this.tendered,
    required this.change,
    required this.canConfirm,
    required this.placing,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final method = ref.watch(_selectedPaymentProvider);
    final items = ref.watch(cartProvider);
    final isCash = method == PaymentMethod.cash;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.point_of_sale_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text('Checkout',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Order summary ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        ...items.map((item) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Text('${item.quantity}×',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(item.product.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textPrimary)),
                                  ),
                                  Text(
                                    '₱${item.total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            )),
                        const Divider(height: 16),
                        Row(
                          children: [
                            const Text('Total',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16)),
                            const Spacer(),
                            Text('₱${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Payment method ───────────────────────────────────
                  const Text('Payment Method',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Row(
                    children: PaymentMethod.values
                        .map((m) => Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(right: 6),
                                child: _PayMethodChip(
                                  method: m,
                                  selected: method == m,
                                  onTap: () => ref
                                      .read(_selectedPaymentProvider
                                          .notifier)
                                      .state = m,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Cash tendered (only for cash) ────────────────────
                  if (isCash) ...[
                    const Text('Amount Tendered',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tenderedController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixText: '₱ ',
                        hintText: subtotal.toStringAsFixed(2),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) =>
                          (context as Element).markNeedsBuild(),
                    ),
                    const SizedBox(height: 8),
                    // Quick-amount buttons
                    _QuickAmounts(
                      subtotal: subtotal,
                      onSelect: (v) {
                        tenderedController.text = v.toStringAsFixed(0);
                        (context as Element).markNeedsBuild();
                      },
                    ),
                    const SizedBox(height: 12),
                    // Change row
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: change >= 0
                            ? AppColors.success.withOpacity(0.08)
                            : AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: change >= 0
                              ? AppColors.success.withOpacity(0.3)
                              : AppColors.danger.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            change >= 0 ? 'Change' : 'Still needed',
                            style: TextStyle(
                                fontSize: 13,
                                color: change >= 0
                                    ? AppColors.success
                                    : AppColors.danger),
                          ),
                          const Spacer(),
                          Text(
                            '₱${change.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: change >= 0
                                    ? AppColors.success
                                    : AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── Confirm button ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: canConfirm && !placing ? onConfirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.divider,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: placing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(
                              isCash
                                  ? 'Confirm & Collect ₱${tendered.toStringAsFixed(2)}'
                                  : 'Confirm Payment',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Receipt view ──────────────────────────────────────────────────────────────

class _ReceiptView extends StatelessWidget {
  final Order order;
  final double tendered;
  final double change;
  final VoidCallback onDone;

  const _ReceiptView({
    required this.order,
    required this.tendered,
    required this.change,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 32),
              ),
              const SizedBox(height: 12),
              const Text('Payment Complete',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              Text('Order #${order.orderNumber}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),

              // Receipt rows
              _ReceiptRow(
                  label: 'Subtotal',
                  value: '₱${order.subtotal.toStringAsFixed(2)}'),
              if (order.taxAmount > 0)
                _ReceiptRow(
                    label: 'Tax',
                    value: '₱${order.taxAmount.toStringAsFixed(2)}'),
              _ReceiptRow(
                  label: 'Total',
                  value: '₱${order.totalAmount.toStringAsFixed(2)}',
                  bold: true),
              if (order.paymentMethod == PaymentMethod.cash) ...[
                _ReceiptRow(
                    label: 'Tendered',
                    value: '₱${tendered.toStringAsFixed(2)}'),
                _ReceiptRow(
                    label: 'Change',
                    value: '₱${change.toStringAsFixed(2)}',
                    valueColor: AppColors.success),
              ],
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('New Order',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight:
                      bold ? FontWeight.w800 : FontWeight.w600,
                  color: valueColor ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ── Payment method chip ───────────────────────────────────────────────────────

class _PayMethodChip extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  const _PayMethodChip({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  String get _label => switch (method) {
        PaymentMethod.cash  => 'Cash',
        PaymentMethod.card  => 'Card',
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.maya  => 'Maya',
      };

  IconData get _icon => switch (method) {
        PaymentMethod.cash  => Icons.payments_outlined,
        PaymentMethod.card  => Icons.credit_card_outlined,
        PaymentMethod.gcash => Icons.phone_android_outlined,
        PaymentMethod.maya  => Icons.account_balance_wallet_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon,
                size: 18,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 3),
            Text(_label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Quick amount buttons ──────────────────────────────────────────────────────

class _QuickAmounts extends StatelessWidget {
  final double subtotal;
  final ValueChanged<double> onSelect;

  const _QuickAmounts({required this.subtotal, required this.onSelect});

  List<double> get _amounts {
    // Generate sensible quick amounts: exact, then rounded up to nearest 50/100
    final exact = subtotal;
    final r50 = (subtotal / 50).ceil() * 50.0;
    final r100 = (subtotal / 100).ceil() * 100.0;
    final r500 = (subtotal / 500).ceil() * 500.0;
    return {exact, r50, r100, r500}
        .where((v) => v >= subtotal)
        .take(4)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _amounts
          .map((amt) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: OutlinedButton(
                  onPressed: () => onSelect(amt),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('₱${amt.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ))
          .toList(),
    );
  }
}