import 'package:flutter/material.dart';
import 'order_summary.dart';
import 'payment_section.dart';
import 'action_buttons.dart';

class CheckoutView extends StatelessWidget {
  final bool isRestaurant;
  final TextEditingController tenderedController;
  final double subtotal;
  final double tendered;
  final double change;
  final bool canConfirm;
  final bool placing;
  final bool sendingToKitchen;
  final VoidCallback onConfirm;
  final VoidCallback onSendToKitchen;
  final VoidCallback onCancel;

  const CheckoutView({
    super.key,
    required this.isRestaurant,
    required this.tenderedController,
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
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          OrderSummary(subtotal: subtotal),
          PaymentSection(
            controller: tenderedController,
            subtotal: subtotal,
            change: change,
          ),
          ActionButtons(
            isRestaurant: isRestaurant,
            canConfirm: canConfirm,
            placing: placing,
            onConfirm: onConfirm,
            onKitchen: onSendToKitchen,
          ),
        ],
      ),
    );
  }
}