// lib/features/pos/widgets/checkout/action_buttons.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/models/order.dart';
import '../../../../core/services/thermal_print_service.dart';
import 'checkout_theme.dart';

// ── Section label (shared) ────────────────────────────────────────────────────

class CheckoutSectionLabel extends StatelessWidget {
  final String text;
  const CheckoutSectionLabel(this.text, {super.key});

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

// ── Action bar (bottom of checkout) ──────────────────────────────────────────

class ActionBar extends StatefulWidget {
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
  // Print Bill
  final Order? currentOrder;
  final String businessName;
  final String? businessAddress;
  final String? tableNumber;
  final String? roomName;

  const ActionBar({
    super.key,
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
    this.currentOrder,
    this.businessName = '',
    this.businessAddress,
    this.tableNumber,
    this.roomName,
  });

  @override
  State<ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<ActionBar> {
  bool _printing = false;

  String get _confirmLabel {
    if (widget.isCash) {
      return 'Collect ₱${widget.tendered.toStringAsFixed(2)}';
    }
    return switch (widget.method) {
      PaymentMethod.gcash => 'Confirm GCash Payment',
      PaymentMethod.maya  => 'Confirm Maya Payment',
      PaymentMethod.card  => 'Confirm Card Payment',
      _                   => 'Confirm Payment',
    };
  }

  Future<void> _printBill() async {
    if (widget.currentOrder == null) return;
    setState(() => _printing = true);
    try {
      await ThermalPrintService.printBill(
        order: widget.currentOrder!,
        businessName: widget.businessName,
        businessAddress: widget.businessAddress,
        tableNumber: widget.tableNumber,
        roomName: widget.roomName,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPrintBill = widget.isRestaurant &&
        widget.existingOrderId != null &&
        widget.currentOrder != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CheckoutTheme.border))),
      child: Column(
        children: [
          Row(
            children: [
              // Kitchen Only — new restaurant orders only
              if (widget.isRestaurant && widget.existingOrderId == null) ...[
                Expanded(
                  child: _GhostButton(
                    label: widget.sendingToKitchen ? 'Sending...' : 'Kitchen Only',
                    icon: Icons.kitchen_outlined,
                    loading: widget.sendingToKitchen,
                    disabled: widget.isBusy,
                    onTap: widget.onSendToKitchen,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // Print Bill — paying an existing restaurant order
              if (showPrintBill) ...[
                Expanded(
                  child: _PrintBillButton(
                    loading: _printing,
                    disabled: widget.isBusy || _printing,
                    onTap: _printBill,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // Pay Now
              Expanded(
                flex: 2,
                child: _ConfirmButton(
                  label: _confirmLabel,
                  loading: widget.placing,
                  enabled: widget.canConfirm && !widget.isBusy,
                  onTap: widget.onConfirm,
                ),
              ),
            ],
          ),
          if (widget.isRestaurant && widget.existingOrderId == null) ...[
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

// ── Confirm button ────────────────────────────────────────────────────────────

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
      onTap: enabled ? () {
        HapticFeedback.mediumImpact();
        onTap();
      } : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? CheckoutTheme.mint : CheckoutTheme.elevated,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [BoxShadow(
                  color: CheckoutTheme.mint.withOpacity(0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                )]
              : [],
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: CheckoutTheme.bg))
            : Text(
                label,
                style: TextStyle(
                    color: enabled ? CheckoutTheme.bg : CheckoutTheme.textLow,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2),
              ),
      ),
    );
  }
}

// ── Ghost button (Kitchen Only) ───────────────────────────────────────────────

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
                width: 18, height: 18,
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

// ── Print Bill button ─────────────────────────────────────────────────────────

class _PrintBillButton extends StatelessWidget {
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _PrintBillButton({
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFB547);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xffffb54712),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: disabled ? CheckoutTheme.border : amber.withOpacity(0.5),
          ),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: amber))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      color: disabled ? CheckoutTheme.textLow : amber,
                      size: 16),
                  const SizedBox(width: 6),
                  Text('Print Bill',
                      style: TextStyle(
                          color: disabled ? CheckoutTheme.textLow : amber,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}