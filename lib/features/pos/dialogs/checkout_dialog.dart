// lib/features/pos/dialogs/checkout_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/order.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/checkout_service.dart';
import '../../../core/services/feature_manager.dart';
import '../../credits/widgets/add_credit_dialog.dart';
import '../../tables/table_provider.dart';
import '../widgets/checkout/action_buttons.dart';
import '../widgets/checkout/checkout_theme.dart';
import '../widgets/checkout/numpad.dart';
import '../widgets/checkout/order_summary.dart';
import '../widgets/checkout/payment_section.dart';
import '../widgets/checkout/reference_number_panel.dart';
import '../widgets/receipt/kitchen_sent_view.dart';
import '../widgets/receipt/restaurant_receipt_view.dart';
import '../widgets/receipt/retail_receipt_view.dart';

// ── Payment method selector ───────────────────────────────────────────────────

final _selectedPaymentProvider =
    StateProvider.autoDispose<PaymentMethod>((ref) => PaymentMethod.cash);

// ── CheckoutDialog ────────────────────────────────────────────────────────────

class CheckoutDialog extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final String? existingOrderId;
  final Order? existingOrder; // ← pass this from pos_screen for Print Bill

  const CheckoutDialog({
    super.key,
    required this.featureManager,
    this.existingOrderId,
    this.existingOrder,
  });

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  final _tenderedController = TextEditingController();
  final _refController = TextEditingController();
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
    _refController.addListener(_rebuild);
  }

  void _onTenderedChanged() => setState(() {});
  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _tenderedController.removeListener(_onTenderedChanged);
    _refController.removeListener(_rebuild);
    _tenderedController.dispose();
    _refController.dispose();
    super.dispose();
  }

  double get _subtotal {
    final items = ref.watch(cartProvider);
    return items.fold(0.0, (s, i) => s + i.total);
  }

  double get _tendered =>
      double.tryParse(_tenderedController.text.replaceAll(',', '')) ?? 0;

  double get _change => (_tendered - _subtotal).clamp(0, double.infinity);

  bool get _canConfirm {
    final items = ref.read(cartProvider);
    if (items.isEmpty && widget.existingOrderId == null) return false;
    final method = ref.read(_selectedPaymentProvider);
    if (method == PaymentMethod.cash) return _tendered >= _subtotal;
    return _refController.text.trim().isNotEmpty;
  }

  Future<void> _placeOrder({required bool payNow}) async {
    final items = ref.read(cartProvider);
    if (items.isEmpty && widget.existingOrderId == null) return;
    if (payNow && widget.existingOrderId == null && !_canConfirm) return;

    final method = ref.read(_selectedPaymentProvider);
    setState(() => payNow ? _placing = true : _sendingToKitchen = true);

    try {
      final result = await ref.read(checkoutServiceProvider).placeOrder(
            context: context,
            payNow: payNow,
            isRestaurant: _isRestaurant,
            hasKitchen: widget.featureManager.hasFeature('kitchen'),
            existingOrderId: widget.existingOrderId,
            paymentMethod: method,
            tendered: _tendered,
            change: _change,
            subtotal: _subtotal,
            items: items,
            discountAmount: 0,
            referenceNumber: _refController.text.trim().isEmpty
                ? null
                : _refController.text.trim(),
          );

      if (!mounted) return;

      switch (result.status) {
        case CheckoutStatus.error:
          setState(() { _placing = false; _sendingToKitchen = false; });
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
        setState(() { _placing = false; _sendingToKitchen = false; });
        _showError('Failed: $e');
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: CheckoutTheme.rose,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_completedOrder != null) {
      if (_sentToKitchenOnly) {
        return KitchenSentView(
          order: _completedOrder!,
          onDone: () => Navigator.of(context).pop(),
          tableNumber: ref.read(tableProvider).selectedTableName,
        );
      }
      final tableState = ref.read(tableProvider);
      return _isRestaurant
          ? RestaurantReceiptView(
              order: _completedOrder!,
              tendered: _savedTendered,
              change: _savedChange,
              onDone: () => Navigator.of(context).pop(),
              showKitchenBanner: widget.existingOrderId == null,
              tableNumber: tableState.selectedTableName,
              roomName: null,
            )
          : RetailReceiptView(
              order: _completedOrder!,
              tendered: _savedTendered,
              change: _savedChange,
              onDone: () => Navigator.of(context).pop(),
            );
    }

    return _CheckoutForm(
      featureManager: widget.featureManager,
      isRestaurant: _isRestaurant,
      existingOrderId: widget.existingOrderId,
      existingOrder: widget.existingOrder,
      tenderedController: _tenderedController,
      refController: _refController,
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

// ── _CheckoutForm ─────────────────────────────────────────────────────────────

class _CheckoutForm extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final bool isRestaurant;
  final String? existingOrderId;
  final Order? existingOrder;
  final TextEditingController tenderedController;
  final TextEditingController refController;
  final double subtotal;
  final double tendered;
  final double change;
  final bool canConfirm;
  final bool placing;
  final bool sendingToKitchen;
  final VoidCallback onConfirm;
  final VoidCallback onSendToKitchen;
  final VoidCallback onCancel;

  const _CheckoutForm({
    required this.featureManager,
    required this.isRestaurant,
    required this.existingOrderId,
    required this.existingOrder,
    required this.tenderedController,
    required this.refController,
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

  @override
  ConsumerState<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends ConsumerState<_CheckoutForm>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _fadeIn = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _numpadTap(String key) {
    final current = widget.tenderedController.text;
    if (key == '⌫') {
      if (current.isNotEmpty) {
        widget.tenderedController.text =
            current.substring(0, current.length - 1);
      }
    } else if (key == '.') {
      if (!current.contains('.')) {
        widget.tenderedController.text =
            current.isEmpty ? '0.' : '$current.';
      }
    } else {
      if (current.contains('.')) {
        final parts = current.split('.');
        if (parts.length > 1 && parts[1].length >= 2) return;
      }
      widget.tenderedController.text = current + key;
    }
    widget.tenderedController.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.tenderedController.text.length),
    );
    HapticFeedback.selectionClick();
  }

  void _setExact() {
    widget.tenderedController.text = widget.subtotal.toStringAsFixed(2);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final method = ref.watch(_selectedPaymentProvider);
    final items = ref.watch(cartProvider);
    final isCash = method == PaymentMethod.cash;
    final isBusy = widget.placing || widget.sendingToKitchen;
    final selectedTable = widget.isRestaurant
        ? ref.watch(tableProvider).selectedTableName
        : null;

    return FadeTransition(
      opacity: _fadeIn,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Container(
          width: 560,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          decoration: BoxDecoration(
            color: CheckoutTheme.bg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: CheckoutTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 60,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CheckoutHeader(
                isRestaurant: widget.isRestaurant,
                tableNumber: selectedTable,
                isBusy: isBusy,
                onCancel: widget.onCancel,
              ),

              if (widget.isRestaurant && selectedTable == null)
                const _NoTableBanner(),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OrderSummaryCard(items: items, subtotal: widget.subtotal),
                      const SizedBox(height: 16),

                      const CheckoutSectionLabel('Payment Method'),
                      const SizedBox(height: 8),
                      PaymentMethodRow(
                        selected: method,
                        isBusy: isBusy,
                        onSelect: (m) {
                          ref.read(_selectedPaymentProvider.notifier).state = m;
                          widget.refController.clear();
                        },
                      ),
                      const SizedBox(height: 16),

                      if (isCash) ...[
                        const CheckoutSectionLabel('Amount Tendered'),
                        const SizedBox(height: 8),
                        TenderedDisplay(
                          tendered: widget.tendered,
                          subtotal: widget.subtotal,
                          change: widget.change,
                          onExact: isBusy ? null : _setExact,
                        ),
                        const SizedBox(height: 10),
                        QuickAmountRow(
                          subtotal: widget.subtotal,
                          isBusy: isBusy,
                          onSelect: (v) {
                            widget.tenderedController.text =
                                v.toStringAsFixed(2);
                            HapticFeedback.mediumImpact();
                          },
                        ),
                        const SizedBox(height: 10),
                        Numpad(onTap: isBusy ? null : _numpadTap),
                        const SizedBox(height: 12),
                        if (!widget.isRestaurant) ...[
                          _UtangButton(
                            isBusy: isBusy,
                            subtotal: widget.subtotal,
                            existingOrderId: widget.existingOrderId,
                            featureManager: widget.featureManager,
                            isRestaurant: widget.isRestaurant,
                            onDone: widget.onCancel,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],

                      if (!isCash) ...[
                        ReferenceNumberPanel(
                          method: method,
                          controller: widget.refController,
                          isBusy: isBusy,
                          subtotal: widget.subtotal,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),

              ActionBar(
                isRestaurant: widget.isRestaurant,
                existingOrderId: widget.existingOrderId,
                isCash: isCash,
                tendered: widget.tendered,
                canConfirm: widget.canConfirm,
                placing: widget.placing,
                sendingToKitchen: widget.sendingToKitchen,
                isBusy: isBusy,
                onConfirm: widget.onConfirm,
                onSendToKitchen: widget.onSendToKitchen,
                method: method,
                // Print Bill
                currentOrder: widget.existingOrder,
                tableNumber: selectedTable,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _CheckoutHeader ───────────────────────────────────────────────────────────

class _CheckoutHeader extends StatelessWidget {
  final bool isRestaurant;
  final String? tableNumber;
  final bool isBusy;
  final VoidCallback onCancel;

  const _CheckoutHeader({
    required this.isRestaurant,
    required this.tableNumber,
    required this.isBusy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CheckoutTheme.border))),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CheckoutTheme.mintDim,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CheckoutTheme.mintBorder),
            ),
            child: Icon(
              isRestaurant
                  ? Icons.restaurant_outlined
                  : Icons.point_of_sale_outlined,
              color: CheckoutTheme.mint,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRestaurant ? 'Restaurant Checkout' : 'Checkout',
                style: const TextStyle(
                    color: CheckoutTheme.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2),
              ),
              if (tableNumber != null)
                Text('Table $tableNumber',
                    style: const TextStyle(
                        color: CheckoutTheme.mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))
              else
                const Text('Ready to collect payment',
                    style: TextStyle(
                        color: CheckoutTheme.textMid, fontSize: 11)),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: isBusy ? null : onCancel,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: CheckoutTheme.elevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close,
                  color: CheckoutTheme.textMid, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _NoTableBanner ────────────────────────────────────────────────────────────

class _NoTableBanner extends StatelessWidget {
  const _NoTableBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xffffb54712),
      child: const Row(
        children: [
          Icon(Icons.table_restaurant_outlined,
              size: 13, color: Color(0xFFFFB547)),
          SizedBox(width: 6),
          Text('No table selected — will be recorded as walk-in',
              style: TextStyle(fontSize: 11, color: Color(0xFFFFB547))),
        ],
      ),
    );
  }
}

// ── _UtangButton ──────────────────────────────────────────────────────────────

class _UtangButton extends ConsumerWidget {
  final bool isBusy;
  final double subtotal;
  final String? existingOrderId;
  final FeatureManager featureManager;
  final bool isRestaurant;
  final VoidCallback onDone;

  const _UtangButton({
    required this.isBusy,
    required this.subtotal,
    required this.existingOrderId,
    required this.featureManager,
    required this.isRestaurant,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: isBusy ? null : () async {
        final result = await showDialog<AddCreditResult>(
          context: context,
          builder: (_) => AddCreditDialog(amount: subtotal),
        );
        if (result == null || !context.mounted) return;

        final checkoutResult =
            await ref.read(checkoutServiceProvider).placeOrder(
                  
                  context: context,
                  payNow: false,
                  isRestaurant: isRestaurant,
                  hasKitchen: featureManager.hasFeature('kitchen'),
                  existingOrderId: existingOrderId,
                  paymentMethod: PaymentMethod.cash,
                  tendered: 0,
                  change: 0,
                  subtotal: subtotal,
                  discountAmount: 0,
                  items: ref.read(cartProvider),
                );

        if (!context.mounted) return;

        if (checkoutResult.status == CheckoutStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      checkoutResult.errorMessage ?? 'Failed to record utang.')),
            ]),
            backgroundColor: CheckoutTheme.rose,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
          return;
        }

        onDone();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.receipt_long_outlined,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Utang recorded for ${result.customer.name}'),
            ]),
            backgroundColor: CheckoutTheme.rose,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: CheckoutTheme.roseDim,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CheckoutTheme.rose.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                color: CheckoutTheme.rose, size: 16),
            SizedBox(width: 8),
            Text('Record as Utang',
                style: TextStyle(
                    color: CheckoutTheme.rose,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}