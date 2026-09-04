// lib/features/pos/dialogs/checkout_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/order.dart';
import '../../../core/models/order_payment.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/checkout_service.dart';
import '../../../core/services/feature_manager.dart';
import '../../credits/widgets/add_credit_dialog.dart';
import '../../tables/table_provider.dart';
import '../../auth/auth_provider.dart';
import '../widgets/checkout/action_buttons.dart';
import '../widgets/checkout/checkout_theme.dart';
import '../widgets/checkout/numpad.dart';
import '../widgets/checkout/order_summary.dart';
import '../widgets/checkout/payment_section.dart';
import '../widgets/checkout/reference_number_panel.dart';
import '../widgets/receipt/kitchen_sent_view.dart';
import '../widgets/receipt/restaurant_receipt_view.dart';
import '../widgets/receipt/retail_receipt_view.dart';
import '../../../core/models/cart_item.dart';
import '../../settings/settings_provider.dart';
import '../../auth/manager_override_dialog.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/providers/role_permissions_provider.dart';
import '../../../core/services/credit_service.dart';

// ── Payment method selector ───────────────────────────────────────────────────

final _selectedPaymentProvider =
    StateProvider.autoDispose<PaymentMethod>((ref) => PaymentMethod.cash);

// ── Split payment support ─────────────────────────────────────────────────────

/// One row in the split-payment editor. Owns its own controllers so typing
/// doesn't rebuild the whole dialog on every keystroke via Riverpod state.
class _SplitLeg {
  PaymentMethod method;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController refController = TextEditingController();

  _SplitLeg(this.method);

  void dispose() {
    amountController.dispose();
    refController.dispose();
  }
}

class _SplitBreakdown {
  /// Amount actually applied to the order for each leg, same order as the
  /// legs list. For a cash leg this may be less than what was typed (the
  /// rest becomes change); for every other method it equals what was typed.
  final List<double> appliedAmounts;
  final double remaining;
  final double change;

  const _SplitBreakdown({
    required this.appliedAmounts,
    required this.remaining,
    required this.change,
  });
}

double _parseAmount(TextEditingController c) =>
    double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

/// Cash legs are treated as "tendered" — only the portion still needed to
/// cover the order is applied; any excess becomes change. Every other
/// method is applied in full as typed (no change on non-cash legs).
_SplitBreakdown _computeSplitBreakdown(List<_SplitLeg> legs, double subtotal) {
  double nonCashApplied = 0;
  for (final leg in legs) {
    if (leg.method != PaymentMethod.cash) {
      nonCashApplied += _parseAmount(leg.amountController);
    }
  }
  double cashNeedRemaining = (subtotal - nonCashApplied).clamp(0.0, double.infinity);  double totalChange = 0;
  final applied = <double>[];

  for (final leg in legs) {
    if (leg.method == PaymentMethod.cash) {
      final tendered = _parseAmount(leg.amountController);
      final legApplied = tendered <= cashNeedRemaining ? tendered : cashNeedRemaining;
      applied.add(legApplied);
      cashNeedRemaining -= legApplied;
      totalChange += (tendered - legApplied);
    } else {
      applied.add(_parseAmount(leg.amountController));
    }
  }

  final totalApplied = applied.fold(0.0, (s, a) => s + a);
  final remaining = (subtotal - totalApplied).clamp(0.0, double.infinity);  return _SplitBreakdown(appliedAmounts: applied, remaining: remaining, change: totalChange);
}

// ── CheckoutDialog ────────────────────────────────────────────────────────────

class CheckoutDialog extends ConsumerStatefulWidget {
  final FeatureManager featureManager;
  final String? existingOrderId;
  final Order? existingOrder;

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
  List<PaymentSplitInput>? _paymentBreakdown;

  bool _splitMode = false;
  final List<_SplitLeg> _splitLegs = [];

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
    for (final leg in _splitLegs) {
      leg.dispose();
    }
    super.dispose();
  }

  // ── Split payment helpers ────────────────────────────────────────────────

  void _toggleSplitMode(bool value) {
    setState(() {
      _splitMode = value;
      if (value && _splitLegs.isEmpty) {
        _addSplitLeg(PaymentMethod.cash);
        _addSplitLeg(PaymentMethod.gcash);
      }
    });
  }

  void _addSplitLeg([PaymentMethod method = PaymentMethod.cash]) {
    final leg = _SplitLeg(method);
    leg.amountController.addListener(_rebuild);
    leg.refController.addListener(_rebuild);
    setState(() => _splitLegs.add(leg));
  }

  void _removeSplitLeg(int index) {
    setState(() {
      _splitLegs[index].dispose();
      _splitLegs.removeAt(index);
    });
  }

  void _setSplitLegMethod(int index, PaymentMethod method) {
    setState(() => _splitLegs[index].method = method);
  }

  double _computeSubtotal() => ref.read(cartProvider.notifier).grandTotal;

  double get _tendered =>
      double.tryParse(_tenderedController.text.replaceAll(',', '')) ?? 0;

  double _computeChange(double subtotal) =>
      (_tendered - subtotal).clamp(0.0, double.infinity);

  bool _computeCanConfirm(double subtotal) {
    final items = ref.read(cartProvider);
    if (items.isEmpty && widget.existingOrderId == null) return false;

    if (_splitMode) {
      if (_splitLegs.length < 2) return false;
      for (final leg in _splitLegs) {
        if (_parseAmount(leg.amountController) <= 0) return false;
        if (leg.method != PaymentMethod.cash &&
            leg.refController.text.trim().isEmpty) {
          return false;
        }
      }
      final breakdown = _computeSplitBreakdown(_splitLegs, subtotal);
      return breakdown.remaining <= 0.005;
    }

    final method = ref.read(_selectedPaymentProvider);
    if (method == PaymentMethod.cash) {
      if (subtotal == 0) return true;
      return _tendered >= subtotal;
    }
    return _refController.text.trim().isNotEmpty;
  }

  Future<void> _placeOrder({required bool payNow}) async {
    final subtotal = _computeSubtotal();
    final items = ref.read(cartProvider);

    if (items.isEmpty && widget.existingOrderId == null) return;
    if (payNow && widget.existingOrderId == null &&
        !_computeCanConfirm(subtotal)) {
      return;
    }

    PaymentMethod method;
    double tendered;
    double change;
    List<PaymentSplitInput>? splitPayments;
    double splitChangeAmount = 0;

    if (_splitMode && payNow) {
      final breakdown = _computeSplitBreakdown(_splitLegs, subtotal);
      splitChangeAmount = breakdown.change;
      splitPayments = [];
      for (int i = 0; i < _splitLegs.length; i++) {
        final applied = breakdown.appliedAmounts[i];
        if (applied <= 0) continue; // fully offset by another leg's overpayment
        final leg = _splitLegs[i];
        splitPayments.add(PaymentSplitInput(
          method: leg.method,
          amount: applied,
          referenceNumber: leg.method == PaymentMethod.cash
              ? null
              : leg.refController.text.trim(),
        ));
      }
      // Dominant leg — used for orders.payment_method / receipt display only;
      // order_payments (written by processSplitPayment) is the real breakdown.
      final dominant =
          splitPayments.reduce((a, b) => b.amount > a.amount ? b : a);
      method = dominant.method;
      tendered = splitPayments.fold(0.0, (s, p) => s + p.amount) + splitChangeAmount;
      change = splitChangeAmount;
    } else {
      method = ref.read(_selectedPaymentProvider);
      tendered = _tendered;
      change = _computeChange(subtotal);
    }

    setState(() => payNow ? _placing = true : _sendingToKitchen = true);

    try {
      final tableState = ref.read(tableProvider);
      final result = await ref.read(checkoutServiceProvider).placeOrder(
            context: context,
            payNow: payNow,
            isRestaurant: _isRestaurant,
            hasKitchen: widget.featureManager.hasFeature('kitchen'),
            existingOrderId: widget.existingOrderId,
            paymentMethod: method,
            tendered: tendered,
            change: change,
            subtotal: subtotal,
            items: items,
            discountAmount: ref.read(cartProvider.notifier).orderDiscountValue,
            tipAmount: ref.read(cartProvider.notifier).tipAmount,
            referenceNumber: _splitMode
                ? null
                : (_refController.text.trim().isEmpty
                    ? null
                    : _refController.text.trim()),
            tableNumber: tableState.selectedTableName,
            splitPayments: splitPayments,
            splitChangeAmount: splitChangeAmount,
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Row(children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Payment confirmed!'),
              ]),
              backgroundColor: CheckoutTheme.mint,
              duration: const Duration(milliseconds: 900),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ));
            await Future.delayed(const Duration(milliseconds: 400));
          }
          if (!mounted) return;
          setState(() {
            _completedOrder = result.order;
            _sentToKitchenOnly = false;
            _savedTendered = result.tendered;
            _savedChange = result.change;
            _paymentBreakdown = splitPayments;
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
    ref.watch(cartProvider);
    final subtotal = _computeSubtotal();
    final tendered = _tendered;
    final change = _computeChange(subtotal);
    final canConfirm = _computeCanConfirm(subtotal);

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
          ?   RestaurantReceiptView(
              order: _completedOrder!,
              tendered: _savedTendered,
              change: _savedChange,
              onDone: () => Navigator.of(context).pop(_completedOrder),
              showKitchenBanner: widget.existingOrderId == null,
              tableNumber: tableState.selectedTableName,
              roomName: null,
              paymentBreakdown: _paymentBreakdown,
            )
          : RetailReceiptView(
              order: _completedOrder!,
              tendered: _savedTendered,
              change: _savedChange,
              onDone: () => Navigator.of(context).pop(_completedOrder),
              paymentBreakdown: _paymentBreakdown,
            );
    }

    return _CheckoutForm(
      featureManager: widget.featureManager,
      isRestaurant: _isRestaurant,
      existingOrderId: widget.existingOrderId,
      existingOrder: widget.existingOrder,
      tenderedController: _tenderedController,
      refController: _refController,
      subtotal: subtotal,
      tendered: tendered,
      change: change,
      canConfirm: canConfirm,
      placing: _placing,
      sendingToKitchen: _sendingToKitchen,
      onConfirm: () => _placeOrder(payNow: true),
      onSendToKitchen: () => _placeOrder(payNow: false),
      onCancel: () => Navigator.of(context).pop(),
      splitMode: _splitMode,
      splitLegs: _splitLegs,
      onToggleSplit: _toggleSplitMode,
      onAddSplitLeg: () => _addSplitLeg(PaymentMethod.gcash),
      onRemoveSplitLeg: _removeSplitLeg,
      onSetSplitLegMethod: _setSplitLegMethod,
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
  final bool splitMode;
  final List<_SplitLeg> splitLegs;
  final ValueChanged<bool> onToggleSplit;
  final VoidCallback onAddSplitLeg;
  final void Function(int) onRemoveSplitLeg;
  final void Function(int, PaymentMethod) onSetSplitLegMethod;

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
    required this.splitMode,
    required this.splitLegs,
    required this.onToggleSplit,
    required this.onAddSplitLeg,
    required this.onRemoveSplitLeg,
    required this.onSetSplitLegMethod,
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
                color: Colors.black.withValues(alpha:0.6),
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
                      OrderSummaryCard(
                        items: items,
                        subtotal: widget.subtotal,
                        itemsTotal:
                            ref.watch(cartProvider.notifier).itemsTotal,
                        tipAmount:
                            ref.watch(cartProvider.notifier).tipAmount,
                        orderDiscountValue:
                            ref.watch(cartProvider.notifier).orderDiscountValue,
                        orderDiscountLabel:
                            ref.watch(cartProvider.notifier).orderDiscountType ==
                                    DiscountType.percentage
                                ? 'Discount (${ref.watch(cartProvider.notifier).orderDiscountAmount.toStringAsFixed(0)}%)'
                                : 'Discount',
                      ),
                      const SizedBox(height: 16),

                      if (!widget.isRestaurant)
                        _OrderTypeSelector(isBusy: isBusy),
                      if (!widget.isRestaurant)
                        const SizedBox(height: 16),

                      if (ref.watch(discountsAllowedProvider))
                        _DiscountButton(isBusy: isBusy),
                      const SizedBox(height: 16),

                      _TipSection(isBusy: isBusy),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          const Expanded(
                            child: CheckoutSectionLabel('Payment Method'),
                          ),
                          GestureDetector(
                            onTap: isBusy
                                ? null
                                : () => widget.onToggleSplit(!widget.splitMode),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Split Payment',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: widget.splitMode
                                          ? CheckoutTheme.mint
                                          : CheckoutTheme.textMid),
                                ),
                                const SizedBox(width: 6),
                                Switch(
                                  value: widget.splitMode,
                                  onChanged:
                                      isBusy ? null : widget.onToggleSplit,
                                  activeThumbColor: CheckoutTheme.mint,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (!widget.splitMode) ...[
                        PaymentMethodRow(
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
                          const CheckoutSectionLabel('Amount Tendered'),
                          const SizedBox(height: 8),
                          TenderedDisplay(
                            tendered: widget.tendered,
                            subtotal: widget.subtotal,
                            change: widget.change,
                            onExact: isBusy ? null : _setExact,
                          ),

                          if (widget.change > 0) ...[
                            const SizedBox(height: 8),
                            ChangeBreakdown(change: widget.change),
                          ],

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
                      ] else ...[
                        _SplitPaymentSection(
                          subtotal: widget.subtotal,
                          legs: widget.splitLegs,
                          isBusy: isBusy,
                          onAddLeg: widget.onAddSplitLeg,
                          onRemoveLeg: widget.onRemoveSplitLeg,
                          onSetMethod: widget.onSetSplitLegMethod,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),

              Consumer(
                builder: (context, ref, _) {
                  final profile = ref.watch(profileProvider);
                  final businessName =
                      profile.asData?.value?.business?.name ?? '';
                  return ActionBar(
                    isRestaurant: widget.isRestaurant,
                    existingOrderId: widget.existingOrderId,
                    isCash: widget.splitMode ? false : isCash,
                    tendered: widget.tendered,
                    canConfirm: widget.canConfirm,
                    placing: widget.placing,
                    sendingToKitchen: widget.sendingToKitchen,
                    isBusy: isBusy,
                    onConfirm: widget.onConfirm,
                    onSendToKitchen: widget.onSendToKitchen,
                    method: widget.splitMode ? PaymentMethod.credit : method,
                    currentOrder: widget.existingOrder,
                    tableNumber: selectedTable,
                    businessName: businessName,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ChangeBreakdown ───────────────────────────────────────────────────────────

class ChangeBreakdown extends StatelessWidget {
  final double change;

  const ChangeBreakdown({
    super.key,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = _calculateBreakdown(change);

    if (change <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CheckoutTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CheckoutTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suggested Change',
            style: TextStyle(
              color: CheckoutTheme.textMid,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: breakdown.entries.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CheckoutTheme.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entry.value} × ₱${entry.key.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: CheckoutTheme.textHigh,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Map<double, int> _calculateBreakdown(double amount) {
    final denominations = [
      1000.0,
      500.0,
      200.0,
      100.0,
      50.0,
      20.0,
      10.0,
      5.0,
      1.0,
    ];

    double remaining = amount.roundToDouble();
    final result = <double, int>{};

    for (final denom in denominations) {
      final count = (remaining ~/ denom);
      if (count > 0) {
        result[denom] = count;
        remaining -= count * denom;
      }
    }

    return result;
  }
}

// ── _SplitPaymentSection ──────────────────────────────────────────────────────

class _SplitPaymentSection extends StatelessWidget {
  final double subtotal;
  final List<_SplitLeg> legs;
  final bool isBusy;
  final VoidCallback onAddLeg;
  final void Function(int) onRemoveLeg;
  final void Function(int, PaymentMethod) onSetMethod;

  const _SplitPaymentSection({
    required this.subtotal,
    required this.legs,
    required this.isBusy,
    required this.onAddLeg,
    required this.onRemoveLeg,
    required this.onSetMethod,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = _computeSplitBreakdown(legs, subtotal);
    final isSettled = breakdown.remaining <= 0.005;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < legs.length; i++) ...[
          _SplitLegRow(
            leg: legs[i],
            isBusy: isBusy,
            canRemove: legs.length > 2,
            onRemove: () => onRemoveLeg(i),
            onSetMethod: (m) => onSetMethod(i, m),
          ),
          const SizedBox(height: 10),
        ],

        if (legs.length < 4)
          GestureDetector(
            onTap: isBusy ? null : onAddLeg,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: CheckoutTheme.elevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CheckoutTheme.border),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      size: 16, color: CheckoutTheme.textMid),
                  SizedBox(width: 6),
                  Text('Add Payment Method',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CheckoutTheme.textMid)),
                ],
              ),
            ),
          ),

        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSettled
                ? CheckoutTheme.mint.withValues(alpha: 0.08)
                : CheckoutTheme.rose.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSettled
                  ? CheckoutTheme.mintBorder
                  : CheckoutTheme.rose.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    isSettled ? 'Fully covered' : 'Remaining',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSettled
                            ? CheckoutTheme.mint
                            : CheckoutTheme.rose),
                  ),
                  const Spacer(),
                  Text(
                    '₱${breakdown.remaining.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isSettled
                            ? CheckoutTheme.mint
                            : CheckoutTheme.rose),
                  ),
                ],
              ),
              if (breakdown.change > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      'Change (cash)',
                      style: TextStyle(
                          fontSize: 12,
                          color: CheckoutTheme.textMid,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      '₱${breakdown.change.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: CheckoutTheme.mint),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SplitLegRow extends StatelessWidget {
  final _SplitLeg leg;
  final bool isBusy;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<PaymentMethod> onSetMethod;

  const _SplitLegRow({
    required this.leg,
    required this.isBusy,
    required this.canRemove,
    required this.onRemove,
    required this.onSetMethod,
  });

  String _label(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.maya => 'Maya',
        PaymentMethod.card => 'Card',
        PaymentMethod.credit => 'Utang',
      };

  @override
  Widget build(BuildContext context) {
    final isCash = leg.method == PaymentMethod.cash;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CheckoutTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CheckoutTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: CheckoutTheme.elevated,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PaymentMethod>(
                      value: leg.method,
                      isDense: true,
                      isExpanded: true,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CheckoutTheme.textHigh),
                      dropdownColor: CheckoutTheme.card,
                      items: PaymentMethod.values
                          .where((m) => m != PaymentMethod.credit)
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(_label(m)),
                              ))
                          .toList(),
                      onChanged: isBusy
                          ? null
                          : (m) {
                              if (m != null) onSetMethod(m);
                            },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: leg.amountController,
                  enabled: !isBusy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CheckoutTheme.textHigh),
                  decoration: InputDecoration(
                    prefixText: '₱',
                    prefixStyle: const TextStyle(
                        fontSize: 13, color: CheckoutTheme.textMid),
                    hintText: '0.00',
                    hintStyle:
                        const TextStyle(color: CheckoutTheme.textLow),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 9),
                    filled: true,
                    fillColor: CheckoutTheme.elevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              if (canRemove) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: isBusy ? null : onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: CheckoutTheme.rose),
                  ),
                ),
              ],
            ],
          ),
          if (!isCash) ...[
            const SizedBox(height: 8),
            TextField(
              controller: leg.refController,
              enabled: !isBusy,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  fontSize: 12, color: CheckoutTheme.textHigh),
              decoration: InputDecoration(
                hintText: '${_label(leg.method)} reference number',
                hintStyle:
                    const TextStyle(fontSize: 12, color: CheckoutTheme.textLow),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                filled: true,
                fillColor: CheckoutTheme.elevated,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ],
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
                    style:
                        TextStyle(color: CheckoutTheme.textMid, fontSize: 11)),
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
      color: const Color(0xFFFFB547),
      child: const Row(
        children: [
          Icon(Icons.table_restaurant_outlined,
              size: 13, color: Colors.white),
          SizedBox(width: 6),
          Text('No table selected — will be recorded as walk-in',
              style: TextStyle(fontSize: 11, color: Colors.white)),
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
              final result = await showDialog<AddCreditResult>(
                context: context,
                builder: (_) => AddCreditDialog(amount: subtotal),
              );
              if (result == null || !context.mounted) return;

              final checkoutResult =
                  await ref.read(checkoutServiceProvider).placeOrder(
                        context: context,
                        payNow: true,
                        isRestaurant: isRestaurant,
                        hasKitchen: featureManager.hasFeature('kitchen'),
                        existingOrderId: existingOrderId,
                        paymentMethod: PaymentMethod.credit,
                        tendered: 0,
                        change: 0,
                        subtotal: subtotal,
                        discountAmount:
                            ref.read(cartProvider.notifier).orderDiscountValue,
                        tipAmount: ref.read(cartProvider.notifier).tipAmount,
                        items: ref.read(cartProvider),
                      );

              if (!context.mounted) return;

              if (checkoutResult.status == CheckoutStatus.error) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
                ));
                return;
              }

              // Record the credit debt against the selected customer
              if (checkoutResult.order != null) {
                try {
                  await ref.read(creditServiceProvider).addCredit(
                    customerId: result.customer.id,
                    businessId: result.customer.businessId,
                    amount: subtotal,
                    orderId: checkoutResult.order!.id,
                    note: 'Utang — order #${checkoutResult.order!.orderNumber}',
                  );
                } catch (e) {
                  debugPrint('[Utang] Credit record failed: $e');
                }
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
                  backgroundColor: CheckoutTheme.mint,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
          border: Border.all(color: CheckoutTheme.rose.withValues(alpha:0.3)),
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

// ── _DiscountButton ───────────────────────────────────────────────────────────

class _DiscountButton extends ConsumerStatefulWidget {
  final bool isBusy;
  const _DiscountButton({required this.isBusy});

  @override
  ConsumerState<_DiscountButton> createState() => _DiscountButtonState();
}

class _DiscountButtonState extends ConsumerState<_DiscountButton> {
  void _showDiscountSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DiscountSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final hasDiscount = notifier.orderDiscountAmount > 0;

    return GestureDetector(
      onTap: widget.isBusy ? null : _showDiscountSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: hasDiscount
              ? CheckoutTheme.rose.withValues(alpha:0.08)
              : CheckoutTheme.elevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasDiscount
                ? CheckoutTheme.rose.withValues(alpha:0.4)
                : CheckoutTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.local_offer_outlined,
                size: 15,
                color:
                    hasDiscount ? CheckoutTheme.rose : CheckoutTheme.textMid),
            const SizedBox(width: 8),
            Text(
              hasDiscount
                  ? notifier.orderDiscountType == DiscountType.percentage
                      ? 'Discount: ${notifier.orderDiscountAmount.toStringAsFixed(0)}% off'
                      : 'Discount: ₱${notifier.orderDiscountAmount.toStringAsFixed(2)} off'
                  : 'Add Discount',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hasDiscount
                      ? CheckoutTheme.rose
                      : CheckoutTheme.textMid),
            ),
            const Spacer(),
            if (hasDiscount)
              GestureDetector(
                onTap: () => ref
                    .read(cartProvider.notifier)
                    .applyOrderDiscount(0, DiscountType.fixed),
                child: const Icon(Icons.close,
                    size: 15, color: CheckoutTheme.rose),
              )
            else
              const Icon(Icons.chevron_right,
                  size: 16, color: CheckoutTheme.textLow),
          ],
        ),
      ),
    );
  }
}

// ── _DiscountSheet ────────────────────────────────────────────────────────────

class _DiscountSheet extends ConsumerStatefulWidget {
  const _DiscountSheet();

  @override
  ConsumerState<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<_DiscountSheet> {
  DiscountType _type = DiscountType.percentage;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(cartProvider.notifier);
    if (notifier.orderDiscountAmount > 0) {
      _type = notifier.orderDiscountType;
      _controller.text = notifier.orderDiscountAmount.toStringAsFixed(
          notifier.orderDiscountType == DiscountType.percentage ? 0 : 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final value = double.tryParse(_controller.text) ?? 0;
    if (value <= 0) {
      ref.read(cartProvider.notifier).applyOrderDiscount(0, _type);
      Navigator.of(context).pop();
      return;
    }

    // Load capability from JSONB — not a hardcoded role check
    final caps = ref.read(activeRoleCapabilitiesProvider).valueOrNull;

    final maxPct = caps?.maxDiscountPercent ?? 0;
    final needsOverride = caps?.requiresManagerForDiscount ?? true;
    bool overrideDone = false;

    // Check 1: value exceeds the role's percentage cap
    if (_type == DiscountType.percentage && maxPct < 100 && value > maxPct) {
      final approved = await requireManagerOverride(
        context: context,
        ref: ref,
        action: 'Apply ${value.toStringAsFixed(0)}% discount (limit: $maxPct%)',
      );
      if (approved == null) return;
      overrideDone = true;
    }

    // Check 2: role always requires override for any discount — but only
    // fire if check 1 didn't already prompt the manager
    if (!overrideDone && needsOverride) {
      final approved = await requireManagerOverride(
        // ignore: use_build_context_synchronously
        context: context,
        ref: ref,
        action: 'Apply ${_type == DiscountType.percentage ? '${value.toStringAsFixed(0)}%' : '₱${value.toStringAsFixed(2)}'} discount',
      );
      if (approved == null) return;
    }

    ref.read(cartProvider.notifier).applyOrderDiscount(value, _type);

    // Audit log
    ref.read(auditServiceProvider).log(
      actionType:  AuditAction.discountApplied,
      entityType:  'cart',
      description: 'Discount applied: '
          '${_type == DiscountType.percentage ? '${value.toStringAsFixed(0)}%' : '₱${value.toStringAsFixed(2)}'} off',
      metadata: {
        'type':  _type == DiscountType.percentage ? 'percentage' : 'fixed',
        'value': value,
      },
    );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isPercent = _type == DiscountType.percentage;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: CheckoutTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: CheckoutTheme.border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: CheckoutTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add Discount',
                style: TextStyle(
                    color: CheckoutTheme.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            Row(
              children: [
                _TypeChip(
                  label: '% Percentage',
                  selected: isPercent,
                  onTap: () => setState(() => _type = DiscountType.percentage),
                ),
                const SizedBox(width: 10),
                _TypeChip(
                  label: '₱ Fixed Amount',
                  selected: !isPercent,
                  onTap: () => setState(() => _type = DiscountType.fixed),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (isPercent) ...[
              Row(
                children: [5, 10, 15, 20].map((pct) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _controller.text = '$pct'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: CheckoutTheme.elevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: CheckoutTheme.border),
                        ),
                        child: Text('$pct%',
                            style: const TextStyle(
                                color: CheckoutTheme.textMid,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  color: CheckoutTheme.textHigh, fontSize: 18),
              decoration: InputDecoration(
                prefixText: isPercent ? null : '₱ ',
                suffixText: isPercent ? '%' : null,
                prefixStyle: const TextStyle(
                    color: CheckoutTheme.textMid, fontSize: 18),
                suffixStyle: const TextStyle(
                    color: CheckoutTheme.textMid, fontSize: 18),
                hintText: isPercent ? '0' : '0.00',
                hintStyle: const TextStyle(color: CheckoutTheme.textLow),
                filled: true,
                fillColor: CheckoutTheme.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: CheckoutTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: CheckoutTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: CheckoutTheme.mint, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            GestureDetector(
              onTap: () => _apply(),
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: CheckoutTheme.mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('Apply Discount',
                    style: TextStyle(
                        color: CheckoutTheme.bg,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _TypeChip ─────────────────────────────────────────────────────────────────

// ── _OrderTypeSelector ────────────────────────────────────────────────────────

class _OrderTypeSelector extends ConsumerWidget {
  final bool isBusy;
  const _OrderTypeSelector({required this.isBusy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cartProvider);
    final current = ref.watch(cartProvider.notifier).orderType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CheckoutSectionLabel('Order Type'),
        const SizedBox(height: 8),
        Row(
          children: [
            _OrderTypeChip(
              label: 'Walk-in',
              icon: Icons.storefront_outlined,
              selected: current == OrderType.walkIn,
              disabled: isBusy,
              onTap: () => ref
                  .read(cartProvider.notifier)
                  .setOrderType(OrderType.walkIn),
            ),
            const SizedBox(width: 8),
            _OrderTypeChip(
              label: 'Takeaway',
              icon: Icons.takeout_dining_outlined,
              selected: current == OrderType.takeOut,
              disabled: isBusy,
              onTap: () => ref
                  .read(cartProvider.notifier)
                  .setOrderType(OrderType.takeOut),
            ),
            const SizedBox(width: 8),
            _OrderTypeChip(
              label: 'Delivery',
              icon: Icons.delivery_dining_outlined,
              selected: current == OrderType.delivery,
              disabled: isBusy,
              onTap: () => ref
                  .read(cartProvider.notifier)
                  .setOrderType(OrderType.delivery),
            ),
          ],
        ),
      ],
    );
  }
}

class _OrderTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _OrderTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? CheckoutTheme.mint.withValues(alpha:0.12)
                : CheckoutTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? CheckoutTheme.mintBorder
                  : CheckoutTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? CheckoutTheme.mint
                      : CheckoutTheme.textMid),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? CheckoutTheme.mint
                          : CheckoutTheme.textMid)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? CheckoutTheme.mint.withValues(alpha:0.12)
              : CheckoutTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? CheckoutTheme.mintBorder : CheckoutTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color:
                  selected ? CheckoutTheme.mint : CheckoutTheme.textMid),
        ),
      ),
    );
  }
}

// ── _TipSection ───────────────────────────────────────────────────────────────

class _TipSection extends ConsumerWidget {
  final bool isBusy;
  const _TipSection({required this.isBusy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final tip = notifier.tipAmount;
    final hasTip = tip > 0;

    return GestureDetector(
      onTap: isBusy ? null : () => _showTipSheet(context, ref),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: hasTip
              ? CheckoutTheme.mint.withValues(alpha:0.08)
              : CheckoutTheme.elevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasTip
                ? CheckoutTheme.mintBorder
                : CheckoutTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.volunteer_activism_outlined,
                size: 15,
                color: hasTip ? CheckoutTheme.mint : CheckoutTheme.textMid),
            const SizedBox(width: 8),
            Text(
              hasTip
                  ? 'Tip: ₱${tip.toStringAsFixed(2)}'
                  : 'Add Tip',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      hasTip ? CheckoutTheme.mint : CheckoutTheme.textMid),
            ),
            const Spacer(),
            if (hasTip)
              GestureDetector(
                onTap: () => ref.read(cartProvider.notifier).setTip(0),
                child: const Icon(Icons.close,
                    size: 15, color: CheckoutTheme.mint),
              )
            else
              const Icon(Icons.chevron_right,
                  size: 16, color: CheckoutTheme.textLow),
          ],
        ),
      ),
    );
  }

  void _showTipSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TipSheet(
        itemsTotal: ref.read(cartProvider.notifier).itemsTotal,
        currentTip: ref.read(cartProvider.notifier).tipAmount,
        onApply: (v) => ref.read(cartProvider.notifier).setTip(v),
      ),
    );
  }
}

// ── _TipSheet ─────────────────────────────────────────────────────────────────

class _TipSheet extends StatefulWidget {
  final double itemsTotal;
  final double currentTip;
  final ValueChanged<double> onApply;

  const _TipSheet({
    required this.itemsTotal,
    required this.currentTip,
    required this.onApply,
  });

  @override
  State<_TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<_TipSheet> {
  static const _presets = [0.05, 0.10, 0.15, 0.20];
  double? _selectedPreset;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.currentTip > 0) {
      _controller.text = widget.currentTip.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(double pct) {
    setState(() {
      _selectedPreset = pct;
      _controller.text =
          (widget.itemsTotal * pct).toStringAsFixed(2);
    });
  }

  void _apply() {
    final value = double.tryParse(_controller.text) ?? 0;
    widget.onApply(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: CheckoutTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: CheckoutTheme.border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: CheckoutTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add Tip',
                style: TextStyle(
                    color: CheckoutTheme.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            Row(
              children: _presets.map((pct) {
                final isSelected = _selectedPreset == pct;
                final pctLabel = '${(pct * 100).toInt()}%';
                final amount = widget.itemsTotal * pct;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _selectPreset(pct),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? CheckoutTheme.mint.withValues(alpha:0.12)
                              : CheckoutTheme.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? CheckoutTheme.mintBorder
                                : CheckoutTheme.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(pctLabel,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? CheckoutTheme.mint
                                        : CheckoutTheme.textMid)),
                            const SizedBox(height: 2),
                            Text(
                              '₱${amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? CheckoutTheme.mint
                                      : CheckoutTheme.textLow),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _controller,
              autofocus: false,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _selectedPreset = null),
              style: const TextStyle(
                  color: CheckoutTheme.textHigh, fontSize: 18),
              decoration: InputDecoration(
                prefixText: '₱ ',
                prefixStyle: const TextStyle(
                    color: CheckoutTheme.textMid, fontSize: 18),
                hintText: '0.00',
                hintStyle:
                    const TextStyle(color: CheckoutTheme.textLow),
                filled: true,
                fillColor: CheckoutTheme.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: CheckoutTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: CheckoutTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: CheckoutTheme.mint, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            GestureDetector(
              onTap: _apply,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: CheckoutTheme.mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('Apply Tip',
                    style: TextStyle(
                        color: CheckoutTheme.bg,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}