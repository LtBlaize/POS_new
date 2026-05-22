// lib/features/pos/widgets/checkout/order_summary.dart
import 'package:flutter/material.dart';
import 'checkout_theme.dart';
import '../../../../core/models/cart_item.dart';

// REPLACE
class OrderSummaryCard extends StatelessWidget {
  final List items;
  final double subtotal;
  final double itemsTotal;
  final double orderDiscountValue;
  final String? orderDiscountLabel;
  final double tipAmount;

  const OrderSummaryCard({
    super.key,
    required this.items,
    required this.subtotal,
    this.itemsTotal = 0,
    this.orderDiscountValue = 0,
    this.orderDiscountLabel,
    this.tipAmount = 0,
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
                      // REPLACE
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: const TextStyle(
                                  fontSize: 13, color: CheckoutTheme.textHigh),
                            ),
                            if (item.discountAmount > 0)
                              Text(
                                item.discountType == DiscountType.percentage
                                    ? '-${item.discountAmount.toStringAsFixed(0)}%'
                                    : '-₱${item.discountValue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: CheckoutTheme.rose,
                                    fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (item.discountAmount > 0)
                            Text(
                              '₱${item.rawTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: CheckoutTheme.textLow,
                                  decoration: TextDecoration.lineThrough),
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
          // REPLACE
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                if (tipAmount > 0) ...[
                  Row(
                    children: [
                      const Text(
                        'Tip',
                        style: TextStyle(
                            color: CheckoutTheme.mint,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '+₱${tipAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: CheckoutTheme.mint,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (orderDiscountValue > 0) ...[
                  Row(
                    children: [
                      Text(
                        orderDiscountLabel ?? 'Order Discount',
                        style: const TextStyle(
                            color: CheckoutTheme.rose,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '-₱${orderDiscountValue.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: CheckoutTheme.rose,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}