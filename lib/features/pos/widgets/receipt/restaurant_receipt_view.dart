// lib/features/pos/widgets/restaurant_receipt_view.dart
import 'package:flutter/material.dart';
import '../../../../core/models/order.dart';
import '../../../../shared/widgets/app_colors.dart';
import '../../../../shared/components/receipt_widgets.dart';

class RestaurantReceiptView extends StatelessWidget {
  final Order order;
  final double tendered;
  final double change;
  final VoidCallback onDone;
  final bool showKitchenBanner; // ← add this

  const RestaurantReceiptView({
    super.key,
    required this.order,
    required this.tendered,
    required this.change,
    required this.onDone,
    this.showKitchenBanner = true, // ← default true for new orders
  });

  static const _dark = Color(0xFF1A1A2E);
  static const _gold = Color(0xFFE8B84B);

  @override
  Widget build(BuildContext context) {
    final isCash = order.paymentMethod == PaymentMethod.cash;
    final tableId = order.tableId;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ─────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: const BoxDecoration(
                  color: _dark,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _gold, width: 2),
                      ),
                      child:
                          const Icon(Icons.check, color: _gold, size: 28),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Order Received',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    if (tableId != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _gold.withOpacity(0.4), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.table_restaurant_outlined,
                                size: 13, color: _gold),
                            const SizedBox(width: 5),
                            Text(
                              'Table $tableId',
                              style: const TextStyle(
                                  color: _gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Order #${order.orderNumber.toString().padLeft(4, '0')}  ·  ${formatDateTime(order.createdAt)}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),

              // ── Kitchen banner ─────────────────────────────────────
              if (showKitchenBanner)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                color: const Color(0xFFFFF3CD),
                child: Row(
                  children: [
                    const Icon(Icons.kitchen_outlined,
                        size: 15, color: Color(0xFF856404)),
                    const SizedBox(width: 8),
                    const Text(
                      'Order sent to kitchen',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF856404),
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF856404).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'QUEUED',
                        style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFF856404),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5),
                      ),
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          children: order.items
                              .map((item) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 4),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: _dark.withOpacity(
                                                0.07),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    6),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${item.quantity}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  color: _dark),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item.product.name,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: AppColors
                                                    .textPrimary,
                                                fontWeight:
                                                    FontWeight.w500),
                                          ),
                                        ),
                                        Text(
                                          '₱${item.total.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight:
                                                  FontWeight.w700,
                                              color: _dark),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Totals ────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _dark.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: _dark.withOpacity(0.08)),
                      ),
                      child: Column(
                        children: [
                          ReceiptRow(
                            label: 'Subtotal',
                            value:
                                '₱${order.subtotal.toStringAsFixed(2)}',
                          ),
                          if (order.taxAmount > 0)
                            ReceiptRow(
                              label: 'VAT (12%)',
                              value:
                                  '₱${order.taxAmount.toStringAsFixed(2)}',
                            ),
                          if (order.discountAmount > 0)
                            ReceiptRow(
                              label: 'Discount',
                              value:
                                  '-₱${order.discountAmount.toStringAsFixed(2)}',
                              valueColor: AppColors.success,
                            ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _dark,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5),
                                ),
                                const Spacer(),
                                Text(
                                  '₱${order.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: _gold,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Payment summary ───────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                AppColors.success.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.payments_outlined,
                                  size: 14, color: AppColors.success),
                              const SizedBox(width: 6),
                              const Text(
                                'Payment',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                              const Spacer(),
                              Text(
                                paymentLabel(order.paymentMethod),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          if (isCash) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              const SizedBox(width: 20),
                              const Text('Tendered',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                              const Spacer(),
                              Text(
                                '₱${tendered.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ]),
                            Row(children: [
                              const SizedBox(width: 20),
                              const Text('Change',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                              const Spacer(),
                              Text(
                                '₱${change.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success),
                              ),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thank you for dining with us!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),

                    // ── Action buttons ────────────────────────────────
                    Row(
                      children: [
                        if (tableId != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onDone,
                              icon: const Icon(
                                  Icons.table_restaurant_outlined,
                                  size: 16),
                              label: const Text('Free Table'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _dark,
                                side: const BorderSide(color: _dark),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                              ),
                            ),
                          ),
                        if (tableId != null) const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: onDone,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _dark,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                            ),
                            child: const Text(
                              'New Order',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                            ),
                          ),
                        ),
                      ],
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