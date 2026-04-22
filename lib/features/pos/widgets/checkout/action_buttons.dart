import 'package:flutter/material.dart';

class ActionButtons extends StatelessWidget {
  final bool isRestaurant;
  final bool canConfirm;
  final bool placing;
  final VoidCallback onConfirm;
  final VoidCallback onKitchen;

  const ActionButtons({
    super.key,
    required this.isRestaurant,
    required this.canConfirm,
    required this.placing,
    required this.onConfirm,
    required this.onKitchen,
  });

  @override
  Widget build(BuildContext context) {
    if (isRestaurant) {
      return Row(
        children: [
          ElevatedButton(
            onPressed: onKitchen,
            child: const Text("Send to Kitchen"),
          ),
          ElevatedButton(
            onPressed: canConfirm ? onConfirm : null,
            child: const Text("Confirm"),
          ),
        ],
      );
    }

    return ElevatedButton(
      onPressed: canConfirm ? onConfirm : null,
      child: const Text("Confirm Payment"),
    );
  }
}