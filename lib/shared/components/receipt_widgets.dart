// lib/features/pos/widgets/receipt_widgets.dart
import 'package:flutter/material.dart';
import '../../../shared/widgets/app_colors.dart';
import '../../../core/models/order.dart';

// ── _ReceiptRow ───────────────────────────────────────────────────────────────

class ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool large;
  final Color? valueColor;

  const ReceiptRow({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.large = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: large ? 14 : 12,
              color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: large ? 16 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── DashedDivider ─────────────────────────────────────────────────────────────

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const dashWidth = 5.0;
      const dashSpace = 4.0;
      final count =
          (constraints.constrainWidth() / (dashWidth + dashSpace)).floor();
      return Row(
        children: List.generate(
          count,
          (_) => Padding(
            padding: const EdgeInsets.only(right: dashSpace),
            child: Container(
                width: dashWidth, height: 1, color: AppColors.divider),
          ),
        ),
      );
    });
  }
}

// ── PayMethodChip ─────────────────────────────────────────────────────────────

class PayMethodChip extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const PayMethodChip({
    super.key,
    required this.method,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  String get _label => switch (method) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.card => 'Card',
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.maya => 'Maya',
      };

  IconData get _icon => switch (method) {
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.card => Icons.credit_card_outlined,
        PaymentMethod.gcash => Icons.phone_android_outlined,
        PaymentMethod.maya => Icons.account_balance_wallet_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? accentColor.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accentColor : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon,
                size: 18,
                color: selected ? accentColor : AppColors.textSecondary),
            const SizedBox(height: 3),
            Text(
              _label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? accentColor : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QuickAmounts ──────────────────────────────────────────────────────────────

class QuickAmounts extends StatelessWidget {
  final double subtotal;
  final Color accentColor;
  final ValueChanged<double> onSelect;

  const QuickAmounts({
    super.key,
    required this.subtotal,
    required this.accentColor,
    required this.onSelect,
  });

  List<double> get _amounts {
    final r50 = (subtotal / 50).ceil() * 50.0;
    final r100 = (subtotal / 100).ceil() * 100.0;
    final r500 = (subtotal / 500).ceil() * 500.0;
    return {subtotal, r50, r100, r500}
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
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '₱${amt.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String formatDateTime(DateTime dt) {
  final h = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  const months = [
    '',
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month]} ${dt.day}, ${dt.year}  $h:$m $period';
}

String paymentLabel(PaymentMethod? method) => switch (method) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.card => 'Card / POS',
      PaymentMethod.gcash => 'GCash',
      PaymentMethod.maya => 'Maya',
      null => 'Unknown',
    };