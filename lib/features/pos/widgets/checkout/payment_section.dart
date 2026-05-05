// lib/features/pos/widgets/checkout/payment_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/models/order.dart';
import 'checkout_theme.dart';

// ── Payment method selector row ───────────────────────────────────────────────

class PaymentMethodRow extends StatelessWidget {
  final PaymentMethod selected;
  final bool isBusy;
  final ValueChanged<PaymentMethod> onSelect;

  const PaymentMethodRow({
    super.key,
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
                  child: PaymentMethodCard(
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

class PaymentMethodCard extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final bool isBusy;
  final VoidCallback onTap;

  const PaymentMethodCard({
    super.key,
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
      onTap: isBusy ? null : () {
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
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : CheckoutTheme.textMid),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tendered display ──────────────────────────────────────────────────────────

class TenderedDisplay extends StatelessWidget {
  final double tendered;
  final double subtotal;
  final double change;
  final VoidCallback? onExact;

  const TenderedDisplay({
    super.key,
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
                      color: isShort
                          ? CheckoutTheme.rose
                          : CheckoutTheme.mint,
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