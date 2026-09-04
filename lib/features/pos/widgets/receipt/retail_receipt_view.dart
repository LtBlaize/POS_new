// lib/features/pos/widgets/retail_receipt_view.dart
import 'package:flutter/material.dart';
import '../../../../core/models/order.dart';
import '../../../../core/models/order_payment.dart';
import '../../../../shared/widgets/app_colors.dart';
import '../../../../shared/components/receipt_widgets.dart';

String _splitLegLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.gcash => 'GCash',
      PaymentMethod.maya => 'Maya',
      PaymentMethod.card => 'Card',
      PaymentMethod.credit => 'Utang',
    };

List<Widget> _retailItemRows(dynamic item) {
  if (!item.isPromo) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text('${item.quantity}×',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(item.product.name,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            ),
            Text('₱${item.total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ];
  }

  return [
    Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Text('${item.quantity}×',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.product.name,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          Text('₱${item.total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
    for (final c in item.promoComponents!)
      Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 2),
        child: Text(
          '${c.quantity}× ${c.variantName != null ? '${c.productName} (${c.variantName})' : c.productName}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
  ];
}

class RetailReceiptView extends StatelessWidget {
  final Order order;
  final double tendered;
  final double change;
  final VoidCallback onDone;
  final List<PaymentSplitInput>? paymentBreakdown;

  const RetailReceiptView({
    super.key,
    required this.order,
    required this.tendered,
    required this.change,
    required this.onDone,
    this.paymentBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final isCash = order.paymentMethod == PaymentMethod.cash;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ─────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Colors.white, size: 40),
                    const SizedBox(height: 8),
                    const Text(
                      'Payment Successful',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Receipt #${order.orderNumber.toString().padLeft(6, '0')}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha:0.75),
                          fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDateTime(order.createdAt),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha:0.6),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),

              // ── Body ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (order.items.isNotEmpty) ...[
                      ...order.items.expand((item) => _retailItemRows(item)),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: DashedDivider(),
                      ),
                    ],
                    ReceiptRow(
                      label: 'Subtotal',
                      value: '₱${order.subtotal.toStringAsFixed(2)}',
                    ),
                    if (order.taxAmount > 0)
                      ReceiptRow(
                        label: 'VAT (12%)',
                        value: '₱${order.taxAmount.toStringAsFixed(2)}',
                      ),
                    if (order.discountAmount > 0)
                      ReceiptRow(
                        label: 'Discount',
                        value:
                            '-₱${order.discountAmount.toStringAsFixed(2)}',
                        valueColor: AppColors.success,
                      ),
                    if (order.tipAmount > 0)
                      ReceiptRow(
                        label: 'Tip',
                        value: '+₱${order.tipAmount.toStringAsFixed(2)}',
                        valueColor: AppColors.primary,
                      ),
                    const SizedBox(height: 4),
                    ReceiptRow(
                      label: 'TOTAL',
                      value: '₱${order.totalAmount.toStringAsFixed(2)}',
                      bold: true,
                      large: true,
                    ),
                    if (order.isSplitPayment &&
                        (paymentBreakdown?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 8),
                      const DashedDivider(),
                      const SizedBox(height: 8),
                      for (final leg in paymentBreakdown!)
                        ReceiptRow(
                          label: 'Payment (${_splitLegLabel(leg.method)})',
                          value: '₱${leg.amount.toStringAsFixed(2)}',
                        ),
                      if (change > 0)
                        ReceiptRow(
                          label: 'Change',
                          value: '₱${change.toStringAsFixed(2)}',
                          valueColor: AppColors.success,
                        ),
                    ] else if (isCash) ...[
                      const SizedBox(height: 8),
                      const DashedDivider(),
                      const SizedBox(height: 8),
                      ReceiptRow(
                        label: 'Payment (Cash)',
                        value: '₱${tendered.toStringAsFixed(2)}',
                      ),
                      ReceiptRow(
                        label: 'Change',
                        value: '₱${change.toStringAsFixed(2)}',
                        valueColor: AppColors.success,
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      ReceiptRow(
                        label: 'Payment',
                        value: paymentLabel(order.paymentMethod),
                        valueColor: AppColors.primary,
                      ),
                    ],
                    const SizedBox(height: 16),
                    const DashedDivider(),
                    const SizedBox(height: 12),
                    const Text(
                      'Thank you for shopping with us!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: onDone,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'New Transaction',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}