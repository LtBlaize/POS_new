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
import '../widgets/checkout/numpad.dart';
import '../widgets/checkout/reference_number_panel.dart';
import '../widgets/receipt/kitchen_sent_view.dart';
import '../widgets/receipt/restaurant_receipt_view.dart';
import '../widgets/receipt/retail_receipt_view.dart';

// ── Payment method selector ───────────────────────────────────────────────────
final _selectedPaymentProvider =
    StateProvider.autoDispose<PaymentMethod>((ref) => PaymentMethod.cash);

// ── Design tokens ─────────────────────────────────────────────────────────────
class CheckoutTheme {
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
  static const maya = Color(0xFF00C472);
  static const card_ = Color(0xFFFFB547);
}

// ── CheckoutDialog ────────────────────────────────────────────────────────────
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

  // FIX 1: watch instead of read so subtotal stays live if cart changes
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
        backgroundColor: CheckoutTheme.rose,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
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

    return _PremiumCheckoutForm(
      featureManager: widget.featureManager,
      isRestaurant: _isRestaurant,
      existingOrderId: widget.existingOrderId,
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

// ── _PremiumCheckoutForm ──────────────────────────────────────────────────────
class _PremiumCheckoutForm extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final bool isRestaurant;
  final String? existingOrderId;
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
                          widget.refController.clear();
                        },
                      ),
                      const SizedBox(height: 16),

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
                        QuickAmountRow(
                          subtotal: widget.subtotal,
                          isBusy: isBusy,
                          // FIX 2: set as fixed-point string so numpad decimal
                          // guard works correctly after a quick-amount tap
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

// ── _Header ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final bool isRestaurant;
  final String? tableNumber;
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
                  letterSpacing: -0.2,
                ),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFFFB54712),
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

// ── _OrderSummaryCard ─────────────────────────────────────────────────────────
class _OrderSummaryCard extends StatelessWidget {
  final List items;
  final double subtotal;

  const _OrderSummaryCard({
    required this.items,
    required this.subtotal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CheckoutTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CheckoutTheme.border),
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
                          color: CheckoutTheme.elevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: CheckoutTheme.mint,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item.product.name,
                            style: const TextStyle(
                                fontSize: 13,
                                color: CheckoutTheme.textHigh)),
                      ),
                      Text(
                        '₱${item.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CheckoutTheme.textHigh),
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
              color: CheckoutTheme.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                const Text('Total',
                    style: TextStyle(
                        color: CheckoutTheme.textMid,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('₱${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: CheckoutTheme.mint,
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

// ── _SectionLabel ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: CheckoutTheme.textLow,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── _PaymentMethodRow ─────────────────────────────────────────────────────────
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
        PaymentMethod.cash =>
          ('Cash', Icons.payments_outlined, CheckoutTheme.mint),
        PaymentMethod.card =>
          ('Card', Icons.credit_card_outlined, CheckoutTheme.card_),
        PaymentMethod.gcash => (
            'GCash',
            Icons.account_balance_wallet_outlined,
            CheckoutTheme.gcash,
          ),
        PaymentMethod.maya =>
          ('Maya', Icons.phone_android_outlined, CheckoutTheme.maya),
      };

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _meta;
    return GestureDetector(
      onTap: isBusy
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : CheckoutTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color.withOpacity(0.6) : CheckoutTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? color : CheckoutTheme.textMid, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : CheckoutTheme.textMid)),
          ],
        ),
      ),
    );
  }
}

// ── _TenderedDisplay ──────────────────────────────────────────────────────────
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
        color: CheckoutTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAmount
              ? (isShort
                  ? CheckoutTheme.rose.withOpacity(0.4)
                  : CheckoutTheme.mintBorder)
              : CheckoutTheme.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('₱',
                  style: TextStyle(
                      color: CheckoutTheme.textMid,
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
                      color: hasAmount
                          ? CheckoutTheme.textHigh
                          : CheckoutTheme.textLow,
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
                    color: CheckoutTheme.elevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('EXACT',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: CheckoutTheme.textMid,
                          letterSpacing: 0.8)),
                ),
              ),
            ],
          ),
          if (hasAmount) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: CheckoutTheme.border),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  isShort ? 'Still needed' : 'Change',
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          isShort ? CheckoutTheme.rose : CheckoutTheme.mint,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '₱${(isShort ? due : change).abs().toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isShort
                          ? CheckoutTheme.rose
                          : CheckoutTheme.mint),
                ),
              ],
            ),
          ],
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
      onTap: isBusy
          ? null
          : () async {
              // Step 1: collect customer info first — bail early if cancelled
              final result = await showDialog<AddCreditResult>(
                context: context,
                builder: (_) => AddCreditDialog(amount: subtotal),
              );
              if (result == null || !context.mounted) return;

              // Step 2: place the order (service clears cart internally)
              final checkoutResult =
                  await ref.read(checkoutServiceProvider).placeOrder(
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

              // FIX: do NOT manually clear cart — service already did it.
              // Only close + show confirmation if the order actually succeeded.
              if (checkoutResult.status == CheckoutStatus.error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(checkoutResult.errorMessage ??
                              'Failed to record utang.')),
                    ]),
                    backgroundColor: CheckoutTheme.rose,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.all(16),
                  ),
                );
                return;
              }

              onDone();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text('Utang recorded for ${result.customer.name}'),
                    ]),
                    backgroundColor: CheckoutTheme.rose,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.all(16),
                  ),
                );
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

// ── _ActionBar ────────────────────────────────────────────────────────────────
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
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CheckoutTheme.border))),
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
                  color: CheckoutTheme.textLow,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

// ── _ConfirmButton ────────────────────────────────────────────────────────────
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
          color: enabled ? CheckoutTheme.mint : CheckoutTheme.elevated,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: CheckoutTheme.mint.withOpacity(0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: CheckoutTheme.bg))
            : Text(
                label,
                style: TextStyle(
                    color:
                        enabled ? CheckoutTheme.bg : CheckoutTheme.textLow,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2),
              ),
      ),
    );
  }
}

// ── _GhostButton ──────────────────────────────────────────────────────────────
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
          color: CheckoutTheme.elevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CheckoutTheme.border),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: CheckoutTheme.textMid))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: CheckoutTheme.textMid, size: 16),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: CheckoutTheme.textMid,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}