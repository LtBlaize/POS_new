// lib/features/pos/widgets/checkout/order_summary.dart
import 'package:flutter/material.dart';
import 'checkout_theme.dart';

class OrderSummaryCard extends StatelessWidget {
  final List items;
  final double subtotal;

  const OrderSummaryCard({
    super.key,
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
                        child: Text(
                          item.product.name,
                          style: const TextStyle(
                              fontSize: 13, color: CheckoutTheme.textHigh),
                        ),
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
            color: CheckoutTheme.border,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                      color: CheckoutTheme.textMid,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '₱${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: CheckoutTheme.mint,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}