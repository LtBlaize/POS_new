import 'package:flutter/material.dart';

class OrderSummary extends StatelessWidget {
  final double subtotal;

  const OrderSummary({super.key, required this.subtotal});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Total: ₱${subtotal.toStringAsFixed(2)}"),
      ],
    );
  }
}