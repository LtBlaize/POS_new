// lib/features/pos/dialogs/checkout_dialog.dart
//
// Premium Checkout Dialog — with reference number support for
// Card / GCash / Maya payments.
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/order.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/checkout_service.dart';
import '../../../core/services/feature_manager.dart';
import '../../tables/table_provider.dart';
import '../widgets/receipt/kitchen_sent_view.dart';
import '../widgets/receipt/retail_receipt_view.dart';
import '../widgets/receipt/restaurant_receipt_view.dart';
import '../../credits/widgets/add_credit_dialog.dart';

// ── Payment method selector ───────────────────────────────────────────────────
final _selectedPaymentProvider =
    StateProvider.autoDispose<PaymentMethod>((ref) => PaymentMethod.cash);

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF0F1117);
  static const card = Color(0xFF1A1D27);
  static const elevated = Color(0xFF22263A);
  static const border = Color(0xFF2E3248);

  static const mint = Color(0xFF00D9A3);
  static const mintDim = Color(0xFF00D9A315);
  static const mintBorder = Color(0xFF00D9A340);

  static const rose = Color(0xFFFF4D6D);
  static const roseDim = Color(0xFFFF4D6D15);


  static const textHigh = Color(0xFFF0F2FF);
  static const textMid = Color(0xFF8B90A8);
  static const textLow = Color(0xFF4A4F6A);

  static const gcash = Color(0xFF007DFF);
  static const gcashDim = Color(0xFF007DFF15);
  static const maya = Color(0xFF00C472);
  static const mayaDim = Color(0xFF00C47215);
  static const card_ = Color(0xFFFFB547);
  static const cardDim = Color(0xFFFFB54715);
}

// ─────────────────────────────────────────────────────────────────────────────
// CheckoutDialog (unchanged outer shell)
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
  final _refController = TextEditingController(); // ← NEW
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
    final items = ref.read(cartProvider);
    return items.fold(0.0, (s, i) => s + i.total);
  }

  double get _tendered =>
      double.tryParse(_tenderedController.text.replaceAll(',', '')) ?? 0;

  double get _change => (_tendered - _subtotal).clamp(0, double.infinity);

  bool get _canConfirm {
    final method = ref.read(_selectedPaymentProvider);
    if (method == PaymentMethod.cash) return _tendered >= _subtotal;
    // Non-cash: reference number required
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
            payNow: payNow,
            isRestaurant: _isRestaurant,
            hasKitchen: widget.featureManager.hasFeature('kitchen'),
            existingOrderId: widget.existingOrderId,
            paymentMethod: method,
            tendered: _tendered,
            change: _change,
            subtotal: _subtotal,
            items: items,
            referenceNumber: _refController.text.trim().isEmpty
                ? null
                : _refController.text.trim(), // ← NEW
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
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: _C.rose,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
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

    return _PremiumCheckoutForm(
      featureManager: widget.featureManager,
      isRestaurant: _isRestaurant,
      existingOrderId: widget.existingOrderId,
      tenderedController: _tenderedController,
      refController: _refController, // ← NEW
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
// _PremiumCheckoutForm
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumCheckoutForm extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final bool isRestaurant;
  final String? existingOrderId;
  final TextEditingController tenderedController;
  final TextEditingController refController; // ← NEW
  final double subtotal;
  final double tendered;
  final double change;
  final bool canConfirm;
  final bool placing;
  final bool sendingToKitchen;
  final VoidCallback onConfirm;
  final VoidCallback onSendToKitchen;
  final VoidCallback onCancel;

  const _PremiumCheckoutForm({
    required this.featureManager,
    required this.isRestaurant,
    required this.existingOrderId,
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
  ConsumerState<_PremiumCheckoutForm> createState() =>
      _PremiumCheckoutFormState();
}

class _PremiumCheckoutFormState extends ConsumerState<_PremiumCheckoutForm>
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
        ? ref.watch(tableProvider).selectedTableNumber
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
            color: _C.bg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _C.border),
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
              _Header(
                isRestaurant: widget.isRestaurant,
                tableNumber: selectedTable,
                isBusy: isBusy,
                onCancel: widget.onCancel,
              ),

              if (widget.isRestaurant && selectedTable == null)
                _NoTableBanner(),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OrderSummaryCard(
                        items: items,
                        subtotal: widget.subtotal,
                        isRestaurant: widget.isRestaurant,
                      ),
                      const SizedBox(height: 16),

                      _SectionLabel('Payment Method'),
                      const SizedBox(height: 8),
                      _PaymentMethodRow(
                        selected: method,
                        isBusy: isBusy,
                        onSelect: (m) {
                          ref
                              .read(_selectedPaymentProvider.notifier)
                              .state = m;
                          // Clear ref field when switching methods
                          widget.refController.clear();
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Cash: numpad flow ────────────────────────
                      if (isCash) ...[
                        _SectionLabel('Amount Tendered'),
                        const SizedBox(height: 8),
                        _TenderedDisplay(
                          tendered: widget.tendered,
                          subtotal: widget.subtotal,
                          change: widget.change,
                          onExact: isBusy ? null : _setExact,
                        ),
                        const SizedBox(height: 10),
                        _QuickAmountRow(
                          subtotal: widget.subtotal,
                          isBusy: isBusy,
                          onSelect: (v) {
                            widget.tenderedController.text =
                                v.toStringAsFixed(0);
                            HapticFeedback.mediumImpact();
                          },
                        ),
                        const SizedBox(height: 10),
                        _Numpad(onTap: isBusy ? null : _numpadTap),
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

                      // ── Non-cash: reference number panel ─────────
                      if (!isCash) ...[
                        _ReferenceNumberPanel(
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

              _ActionBar(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reference Number Panel  ← NEW
// ─────────────────────────────────────────────────────────────────────────────
class _ReferenceNumberPanel extends StatelessWidget {
  final PaymentMethod method;
  final TextEditingController controller;
  final bool isBusy;
  final double subtotal;

  const _ReferenceNumberPanel({
    required this.method,
    required this.controller,
    required this.isBusy,
    required this.subtotal,
  });

  (Color accent, Color dim, String label, String hint, IconData icon)
      get _meta => switch (method) {
            PaymentMethod.gcash => (
                _C.gcash,
                _C.gcashDim,
                'GCash Reference',
                'e.g. 1234567890',
                Icons.account_balance_wallet_outlined,
              ),
            PaymentMethod.maya => (
                _C.maya,
                _C.mayaDim,
                'Maya Reference',
                'e.g. TXN-XXXXXXXXXX',
                Icons.phone_android_outlined,
              ),
            PaymentMethod.card => (
                _C.card_,
                _C.cardDim,
                'Card Approval Code',
                'e.g. 123456',
                Icons.credit_card_outlined,
              ),
            _ => (
                _C.mint,
                _C.mintDim,
                'Reference',
                '',
                Icons.receipt_outlined,
              ),
          };

  @override
  Widget build(BuildContext context) {
    final (accent, dim, label, hint, icon) = _meta;
    final hasValue = controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Total reminder ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dim,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amount to collect',
                    style: TextStyle(
                      fontSize: 11,
                      color: accent.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '₱${subtotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  method == PaymentMethod.card
                      ? 'CARD'
                      : method == PaymentMethod.gcash
                          ? 'GCASH'
                          : 'MAYA',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _SectionLabel(label),
        const SizedBox(height: 8),

        // ── Reference input ───────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasValue
                  ? accent.withOpacity(0.5)
                  : _C.border,
              width: hasValue ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            enabled: !isBusy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
              color: hasValue ? _C.textHigh : _C.textMid,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: _C.textLow,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(
                  Icons.tag_rounded,
                  color: hasValue ? accent : _C.textLow,
                  size: 20,
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: hasValue
                  ? GestureDetector(
                      onTap: controller.clear,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.close,
                            color: _C.textMid, size: 18),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 16),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Validation hint ───────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: hasValue
              ? Row(
                  key: const ValueKey('ok'),
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: accent, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      'Reference number entered',
                      style: TextStyle(
                          fontSize: 12,
                          color: accent,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey('hint'),
                  children: [
                    const Icon(Icons.info_outline,
                        color: _C.textLow, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      'Enter the reference number from the payment app',
                      style: const TextStyle(
                          fontSize: 12, color: _C.textLow),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final bool isRestaurant;
  final int? tableNumber;
  final bool isBusy;
  final VoidCallback onCancel;

  const _Header({
    required this.isRestaurant,
    required this.tableNumber,
    required this.isBusy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration:
          const BoxDecoration(border: Border(bottom: BorderSide(color: _C.border))),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _C.mintDim,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.mintBorder),
            ),
            child: Icon(
              isRestaurant
                  ? Icons.restaurant_outlined
                  : Icons.point_of_sale_outlined,
              color: _C.mint,
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
                  color: _C.textHigh,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (tableNumber != null)
                Text('Table $tableNumber',
                    style: const TextStyle(
                        color: _C.mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))
              else
                const Text('Ready to collect payment',
                    style: TextStyle(color: _C.textMid, fontSize: 11)),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: isBusy ? null : onCancel,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _C.elevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: _C.textMid, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No-table banner
// ─────────────────────────────────────────────────────────────────────────────
class _NoTableBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFFFB54712),
      child: Row(
        children: const [
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

// ─────────────────────────────────────────────────────────────────────────────
// Order summary card
// ─────────────────────────────────────────────────────────────────────────────
class _OrderSummaryCard extends StatelessWidget {
  final List items;
  final double subtotal;
  final bool isRestaurant;

  const _OrderSummaryCard({
    required this.items,
    required this.subtotal,
    required this.isRestaurant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              children: items.map<Widget>((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _C.elevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _C.mint,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item.product.name,
                            style: const TextStyle(
                                fontSize: 13, color: _C.textHigh)),
                      ),
                      Text(
                        '₱${item.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _C.textHigh),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              height: 1,
              color: _C.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                const Text('Total',
                    style: TextStyle(
                        color: _C.textMid,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('₱${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: _C.mint,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _C.textLow,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment method row
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentMethodRow extends StatelessWidget {
  final PaymentMethod selected;
  final bool isBusy;
  final ValueChanged<PaymentMethod> onSelect;

  const _PaymentMethodRow({
    required this.selected,
    required this.isBusy,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: PaymentMethod.values
          .map((m) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _MethodCard(
                    method: m,
                    selected: selected == m,
                    isBusy: isBusy,
                    onTap: () => onSelect(m),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final bool isBusy;
  final VoidCallback onTap;

  const _MethodCard({
    required this.method,
    required this.selected,
    required this.isBusy,
    required this.onTap,
  });

  (String label, IconData icon, Color color) get _meta => switch (method) {
        PaymentMethod.cash => ('Cash', Icons.payments_outlined, _C.mint),
        PaymentMethod.card =>
          ('Card', Icons.credit_card_outlined, _C.card_),
        PaymentMethod.gcash => (
            'GCash',
            Icons.account_balance_wallet_outlined,
            _C.gcash
          ),
        PaymentMethod.maya =>
          ('Maya', Icons.phone_android_outlined, _C.maya),
      };

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _meta;
    return GestureDetector(
      onTap: isBusy ? null : () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : _C.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color.withOpacity(0.6) : _C.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : _C.textMid, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : _C.textMid)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tendered display (cash only)
// ─────────────────────────────────────────────────────────────────────────────
class _TenderedDisplay extends StatelessWidget {
  final double tendered;
  final double subtotal;
  final double change;
  final VoidCallback? onExact;

  const _TenderedDisplay({
    required this.tendered,
    required this.subtotal,
    required this.change,
    required this.onExact,
  });

  @override
  Widget build(BuildContext context) {
    final hasAmount = tendered > 0;
    final due = subtotal - tendered;
    final isShort = due > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAmount
              ? (isShort ? _C.rose.withOpacity(0.4) : _C.mintBorder)
              : _C.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('₱',
                  style: TextStyle(
                      color: _C.textMid,
                      fontSize: 18,
                      fontWeight: FontWeight.w400)),
              const SizedBox(width: 4),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  child: Text(
                    tendered > 0 ? tendered.toStringAsFixed(2) : '0.00',
                    key: ValueKey(tendered),
                    style: TextStyle(
                      color: hasAmount ? _C.textHigh : _C.textLow,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onExact,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _C.elevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('EXACT',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _C.textMid,
                          letterSpacing: 0.8)),
                ),
              ),
            ],
          ),
          if (hasAmount) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: _C.border),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(isShort ? 'Still needed' : 'Change',
                    style: TextStyle(
                        fontSize: 13,
                        color: isShort ? _C.rose : _C.mint,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('₱${(isShort ? due : change).abs().toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isShort ? _C.rose : _C.mint)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick amount row
// ─────────────────────────────────────────────────────────────────────────────
class _QuickAmountRow extends StatelessWidget {
  final double subtotal;
  final bool isBusy;
  final ValueChanged<double> onSelect;

  const _QuickAmountRow({
    required this.subtotal,
    required this.isBusy,
    required this.onSelect,
  });

  List<double> get _amounts {
    final amounts = <double>[];
    final niceBills = [20, 50, 100, 200, 500, 1000];
    for (final b in niceBills) {
      final rounded = (subtotal / b).ceil() * b.toDouble();
      if (!amounts.contains(rounded) && rounded >= subtotal) {
        amounts.add(rounded);
        if (amounts.length == 4) break;
      }
    }
    return amounts;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _amounts
          .map((v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: isBusy ? null : () => onSelect(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _C.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _C.border),
                      ),
                      alignment: Alignment.center,
                      child: Text('₱${v.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: _C.textHigh,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numpad
// ─────────────────────────────────────────────────────────────────────────────
class _Numpad extends StatelessWidget {
  final ValueChanged<String>? onTap;
  const _Numpad({required this.onTap});

  static const _keys = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: row.map((k) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NumpadKey(
                    label: k,
                    isBackspace: k == '⌫',
                    onTap: onTap == null ? null : () => onTap!(k),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _NumpadKey extends StatefulWidget {
  final String label;
  final bool isBackspace;
  final VoidCallback? onTap;

  const _NumpadKey({
    required this.label,
    required this.isBackspace,
    required this.onTap,
  });

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _press() async {
    if (widget.onTap == null) return;
    _ac.forward();
    await Future.delayed(const Duration(milliseconds: 80));
    _ac.reverse();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _press,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: widget.isBackspace ? _C.roseDim : _C.elevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isBackspace
                  ? _C.rose.withOpacity(0.25)
                  : _C.border,
            ),
          ),
          alignment: Alignment.center,
          child: widget.isBackspace
              ? const Icon(Icons.backspace_outlined,
                  color: _C.rose, size: 18)
              : Text(widget.label,
                  style: const TextStyle(
                      color: _C.textHigh,
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utang button
// ─────────────────────────────────────────────────────────────────────────────
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
      onTap: isBusy
          ? null
          : () async {
              final result = await showDialog<AddCreditResult>(
                context: context,
                builder: (_) => AddCreditDialog(amount: subtotal),
              );
              if (result != null && context.mounted) {
                await ref.read(checkoutServiceProvider).placeOrder(
                      payNow: false,
                      isRestaurant: isRestaurant,
                      hasKitchen: featureManager.hasFeature('kitchen'),
                      existingOrderId: existingOrderId,
                      paymentMethod: PaymentMethod.cash,
                      tendered: 0,
                      change: 0,
                      subtotal: subtotal,
                      items: ref.read(cartProvider),
                    );
                ref.read(cartProvider.notifier).clear();
                onDone();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(children: [
                        const Icon(Icons.receipt_long_outlined,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                            'Utang recorded for ${result.customer.name}'),
                      ]),
                      backgroundColor: _C.rose,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }
              }
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: _C.roseDim,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.rose.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.receipt_long_outlined, color: _C.rose, size: 16),
            SizedBox(width: 8),
            Text('Record as Utang',
                style: TextStyle(
                    color: _C.rose,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom action bar
// ─────────────────────────────────────────────────────────────────────────────
class _ActionBar extends StatelessWidget {
  final bool isRestaurant;
  final String? existingOrderId;
  final bool isCash;
  final double tendered;
  final bool canConfirm;
  final bool placing;
  final bool sendingToKitchen;
  final bool isBusy;
  final VoidCallback onConfirm;
  final VoidCallback onSendToKitchen;
  final PaymentMethod method;

  const _ActionBar({
    required this.isRestaurant,
    required this.existingOrderId,
    required this.isCash,
    required this.tendered,
    required this.canConfirm,
    required this.placing,
    required this.sendingToKitchen,
    required this.isBusy,
    required this.onConfirm,
    required this.onSendToKitchen,
    required this.method,
  });

  String get _confirmLabel {
    if (isCash) return 'Collect ₱${tendered.toStringAsFixed(2)}';
    return switch (method) {
      PaymentMethod.gcash => 'Confirm GCash Payment',
      PaymentMethod.maya => 'Confirm Maya Payment',
      PaymentMethod.card => 'Confirm Card Payment',
      _ => 'Confirm Payment',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: _C.border))),
      child: Column(
        children: [
          Row(
            children: [
              if (isRestaurant && existingOrderId == null) ...[
                Expanded(
                  child: _GhostButton(
                    label: sendingToKitchen ? 'Sending...' : 'Kitchen Only',
                    icon: Icons.kitchen_outlined,
                    loading: sendingToKitchen,
                    disabled: isBusy,
                    onTap: onSendToKitchen,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: _ConfirmButton(
                  label: _confirmLabel,
                  loading: placing,
                  enabled: canConfirm && !isBusy,
                  onTap: onConfirm,
                ),
              ),
            ],
          ),
          if (isRestaurant && existingOrderId == null) ...[
            const SizedBox(height: 8),
            const Text(
              '"Kitchen Only" sends to cook — customer pays later',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: _C.textLow,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _ConfirmButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.mediumImpact();
              onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? _C.mint : _C.elevated,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _C.mint.withOpacity(0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: _C.bg))
            : Text(label,
                style: TextStyle(
                    color: enabled ? _C.bg : _C.textLow,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _GhostButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _C.elevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _C.textMid))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: _C.textMid, size: 16),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: _C.textMid,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}