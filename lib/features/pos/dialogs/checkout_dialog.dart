// lib/features/pos/dialogs/checkout_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/order.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/checkout_service.dart';
import '../../../core/services/feature_manager.dart';
import '../../../shared/widgets/app_colors.dart';
import '../../tables/table_provider.dart';
import '../widgets/receipt/kitchen_sent_view.dart';
import '../widgets/receipt/retail_receipt_view.dart';
import '../widgets/receipt/restaurant_receipt_view.dart';
import '../../../shared/components/receipt_widgets.dart';

// ── Payment method selector ───────────────────────────────────────────────────
final _selectedPaymentProvider =
    StateProvider.autoDispose<PaymentMethod>((ref) => PaymentMethod.cash);

// ─────────────────────────────────────────────────────────────────────────────
// CheckoutDialog
// ─────────────────────────────────────────────────────────────────────────────

class CheckoutDialog extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final String? existingOrderId;

  const CheckoutDialog({
    super.key,
    required this.featureManager,
    this.existingOrderId,
  });

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  final _tenderedController = TextEditingController();
  bool _placing = false;
  bool _sendingToKitchen = false;
  Order? _completedOrder;
  bool _sentToKitchenOnly = false;
  double _savedTendered = 0;
  double _savedChange = 0;

  bool get _isRestaurant =>
      widget.featureManager.hasFeature('kitchen') ||
      widget.featureManager.hasFeature('tables');

  @override
  void initState() {
    super.initState();
    _tenderedController.addListener(_onTenderedChanged);
  }

  void _onTenderedChanged() => setState(() {});

  @override
  void dispose() {
    _tenderedController.removeListener(_onTenderedChanged);
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
    return true;
  }

  Future<void> _placeOrder({required bool payNow}) async {
    final items = ref.read(cartProvider);
    if (items.isEmpty && widget.existingOrderId == null) return;
    if (payNow && widget.existingOrderId == null && !_canConfirm) return;

    final method = ref.read(_selectedPaymentProvider);
    setState(() => payNow ? _placing = true : _sendingToKitchen = true);

    try {
      final result = await ref.read(checkoutServiceProvider).placeOrder(
            payNow: payNow,
            isRestaurant: _isRestaurant,
            hasKitchen: widget.featureManager.hasFeature('kitchen'),
            existingOrderId: widget.existingOrderId,
            paymentMethod: method,
            tendered: _tendered,
            change: _change,
            subtotal: _subtotal,
            items: items,
          );

      if (!mounted) return;

      switch (result.status) {
        case CheckoutStatus.error:
          setState(() {
            _placing = false;
            _sendingToKitchen = false;
          });
          _showError(result.errorMessage ?? 'An error occurred.');

        case CheckoutStatus.sentToKitchen:
          setState(() {
            _completedOrder = result.order;
            _sentToKitchenOnly = true;
            _savedTendered = 0;
            _savedChange = 0;
            _sendingToKitchen = false;
          });

        case CheckoutStatus.paid:
          setState(() {
            _completedOrder = result.order;
            _sentToKitchenOnly = false;
            _savedTendered = result.tendered;
            _savedChange = result.change;
            _placing = false;
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _placing = false;
          _sendingToKitchen = false;
        });
        _showError('Failed: $e');
      }
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
    if (_completedOrder != null) {
      if (_sentToKitchenOnly) {
        final tableNumber = ref.read(tableProvider).selectedTableNumber;  
        return KitchenSentView(
          order: _completedOrder!,
          onDone: () => Navigator.of(context).pop(),
          tableNumber: tableNumber,
        );
      }
      final tableState = ref.read(tableProvider);
      final tableNumber = tableState.selectedTableNumber;
      final roomId = tableState.selectedRoomId;

      return _isRestaurant
          ? RestaurantReceiptView(
              order: _completedOrder!,
              tendered: _savedTendered,
              change: _savedChange,
              onDone: () => Navigator.of(context).pop(),
              showKitchenBanner: widget.existingOrderId == null,
              tableNumber: tableNumber,
              roomName: roomId,
            )
          : RetailReceiptView(
              order: _completedOrder!,
              tendered: _savedTendered,
              change: _savedChange,
              onDone: () => Navigator.of(context).pop(),
            );
    }

    return _CheckoutFormView(
      featureManager: widget.featureManager,
      isRestaurant: _isRestaurant,
      existingOrderId: widget.existingOrderId,
      tenderedController: _tenderedController,
      subtotal: _subtotal,
      tendered: _tendered,
      change: _change,
      canConfirm: _canConfirm,
      placing: _placing,
      sendingToKitchen: _sendingToKitchen,
      onConfirm: () => _placeOrder(payNow: true),
      onSendToKitchen: () => _placeOrder(payNow: false),
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Checkout form view
// ─────────────────────────────────────────────────────────────────────────────

class _CheckoutFormView extends ConsumerWidget {
  final FeatureManager featureManager;
  final bool isRestaurant;
  final String? existingOrderId;
  final TextEditingController tenderedController;
  final double subtotal;
  final double tendered;
  final double change;
  final bool canConfirm;
  final bool placing;
  final bool sendingToKitchen;
  final VoidCallback onConfirm;
  final VoidCallback onSendToKitchen;
  final VoidCallback onCancel;

  const _CheckoutFormView({
    required this.featureManager,
    required this.isRestaurant,
    required this.existingOrderId,
    required this.tenderedController,
    required this.subtotal,
    required this.tendered,
    required this.change,
    required this.canConfirm,
    required this.placing,
    required this.sendingToKitchen,
    required this.onConfirm,
    required this.onSendToKitchen,
    required this.onCancel,
  });

  static const _dark = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final method = ref.watch(_selectedPaymentProvider);
    final items = ref.watch(cartProvider);
    final isCash = method == PaymentMethod.cash;
    final isBusy = placing || sendingToKitchen;
    final selectedTable =
        isRestaurant ? ref.watch(tableProvider).selectedTableNumber : null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Title bar ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: isRestaurant ? _dark : AppColors.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isRestaurant
                          ? Icons.restaurant_outlined
                          : Icons.point_of_sale_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isRestaurant ? 'Restaurant Checkout' : 'Checkout',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    if (isRestaurant && selectedTable != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Table $selectedTable',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      onPressed: isBusy ? null : onCancel,
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              if (isRestaurant && selectedTable == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: AppColors.warning.withOpacity(0.08),
                  child: Row(
                    children: [
                      Icon(Icons.table_restaurant_outlined,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 6),
                      const Text(
                        'No table selected — order will be walk-in',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Order items ──────────────────────────────────
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
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: (isRestaurant
                                                ? _dark
                                                : AppColors.primary)
                                            .withOpacity(0.08),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${item.quantity}',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: isRestaurant
                                                  ? _dark
                                                  : AppColors.primary),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.product.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textPrimary),
                                      ),
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
                              Text(
                                '₱${subtotal.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: isRestaurant
                                        ? _dark
                                        : AppColors.primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Payment method ───────────────────────────────
                    const Text(
                      'Payment Method',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: PaymentMethod.values
                          .map((m) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: PayMethodChip(
                                    method: m,
                                    selected: method == m,
                                    accentColor: isRestaurant
                                        ? _dark
                                        : AppColors.primary,
                                    onTap: isBusy
                                        ? () {}
                                        : () => ref
                                            .read(_selectedPaymentProvider
                                                .notifier)
                                            .state = m,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Cash tendered ────────────────────────────────
                    if (isCash) ...[
                      const Text(
                        'Amount Tendered',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: tenderedController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        autofocus: true,
                        enabled: !isBusy,
                        decoration: InputDecoration(
                          prefixText: '₱ ',
                          hintText: subtotal.toStringAsFixed(2),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: isRestaurant
                                    ? _dark
                                    : AppColors.primary,
                                width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      QuickAmounts(
                        subtotal: subtotal,
                        accentColor:
                            isRestaurant ? _dark : AppColors.primary,
                        onSelect: (v) {
                          tenderedController.text =
                              v.toStringAsFixed(0);
                        },
                      ),
                      const SizedBox(height: 12),
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

                    // ── Action buttons ───────────────────────────────
                    if (isRestaurant) ...[
                      Row(
                        children: [
                          if (existingOrderId == null) ...[
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      isBusy ? null : onSendToKitchen,
                                  icon: sendingToKitchen
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(
                                          Icons.kitchen_outlined,
                                          size: 16),
                                  label: Text(
                                    sendingToKitchen
                                        ? 'Sending...'
                                        : 'Send to Kitchen',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _dark,
                                    side: const BorderSide(
                                        color: _dark, width: 1.5),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            flex: existingOrderId == null ? 2 : 1,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: canConfirm && !isBusy
                                    ? onConfirm
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      AppColors.divider,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
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
                                            ? 'Collect ₱${tendered.toStringAsFixed(2)} & Confirm'
                                            : 'Confirm Payment',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (existingOrderId == null)
                        Center(
                          child: Text(
                            '"Send to Kitchen" sends the order to cook — customer pays later',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary
                                    .withOpacity(0.7),
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed:
                              canConfirm && !isBusy ? onConfirm : null,
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
                                      ? 'Collect ₱${tendered.toStringAsFixed(2)} & Confirm'
                                      : 'Confirm Payment',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}