import 'package:flutter/material.dart';

class PaymentSection extends StatelessWidget {
  final TextEditingController controller;
  final double subtotal;
  final double change;

  const PaymentSection({
    super.key,
    required this.controller,
    required this.subtotal,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: "Amount Tendered"),
        ),
        Text("Change: ₱${change.toStringAsFixed(2)}"),
      ],
    );
  }
}