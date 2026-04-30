// lib/features/pos/widgets/checkout/reference_number_panel.dart
import 'package:flutter/material.dart';

import '../../../../core/models/order.dart';
import 'checkout_theme.dart';

class ReferenceNumberPanel extends StatelessWidget {
  final PaymentMethod method;
  final TextEditingController controller;
  final bool isBusy;
  final double subtotal;

  const ReferenceNumberPanel({
    super.key,
    required this.method,
    required this.controller,
    required this.isBusy,
    required this.subtotal,
  });

  (Color accent, Color dim, String label, String hint, IconData icon)
      get _meta => switch (method) {
            PaymentMethod.gcash => (
                CheckoutTheme.gcash,
                CheckoutTheme.gcashDim,
                'GCash Reference',
                'e.g. 1234567890',
                Icons.account_balance_wallet_outlined,
              ),
            PaymentMethod.maya => (
                CheckoutTheme.maya,
                CheckoutTheme.mayaDim,
                'Maya Reference',
                'e.g. TXN-XXXXXXXXXX',
                Icons.phone_android_outlined,
              ),
            PaymentMethod.card => (
                CheckoutTheme.card_,
                CheckoutTheme.cardDim,
                'Card Approval Code',
                'e.g. 123456',
                Icons.credit_card_outlined,
              ),
            _ => (
                CheckoutTheme.mint,
                CheckoutTheme.mintDim,
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
        // ── Total reminder ──────────────────────────────────────────────
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

        // ── Reference input ─────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: CheckoutTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasValue ? accent.withOpacity(0.5) : CheckoutTheme.border,
              width: hasValue ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            enabled: !isBusy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
              color: hasValue ? CheckoutTheme.textHigh : CheckoutTheme.textMid,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: CheckoutTheme.textLow,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(
                  Icons.tag_rounded,
                  color: hasValue ? accent : CheckoutTheme.textLow,
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
                            color: CheckoutTheme.textMid, size: 18),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Validation hint ─────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: hasValue
              ? Row(
                  key: const ValueKey('ok'),
                  children: [
                    Icon(Icons.check_circle_outline, color: accent, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      'Reference number entered',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : const Row(
                  key: ValueKey('hint'),
                  children: [
                    Icon(Icons.info_outline,
                        color: CheckoutTheme.textLow, size: 14),
                    SizedBox(width: 5),
                    Text(
                      'Enter the reference number from the payment app',
                      style: TextStyle(
                          fontSize: 12, color: CheckoutTheme.textLow),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Private to this file — only used by ReferenceNumberPanel ──────────────────
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