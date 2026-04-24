// lib/features/credits/widgets/pay_credit_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/credit.dart';
import '../../../core/providers/credit_provider.dart';

class PayCreditDialog extends ConsumerStatefulWidget {
  final CreditCustomer customer;
  const PayCreditDialog({super.key, required this.customer});

  @override
  ConsumerState<PayCreditDialog> createState() => _PayCreditDialogState();
}

class _PayCreditDialogState extends ConsumerState<PayCreditDialog> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _bg = Color(0xFF0F1223);
  static const _surface = Color(0xFF1A1F35);
  static const _green = Color(0xFF10B981);

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setFull() =>
      _amountCtrl.text = widget.customer.totalOwed.toStringAsFixed(2);

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > widget.customer.totalOwed) {
      setState(() => _error = 'Amount exceeds balance');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await ref.read(creditCustomersProvider.notifier).recordPayment(
          customerId: widget.customer.id,
          amount: amount,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final owed = widget.customer.totalOwed;
    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.payments_outlined,
                      color: _green, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Record Payment',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(widget.customer.name,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Balance chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current Balance',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 13)),
                  Text('₱${owed.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Color(0xFFE94560),
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Amount field
            _Field(
              controller: _amountCtrl,
              label: 'Payment Amount',
              prefix: '₱',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
              ],
              onChanged: (_) => setState(() => _error = null),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _setFull,
                child: Text('Pay full ₱${owed.toStringAsFixed(2)}',
                    style: const TextStyle(color: _green, fontSize: 12)),
              ),
            ),

            _Field(
              controller: _noteCtrl,
              label: 'Note (optional)',
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFE94560), fontSize: 12)),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Confirm',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.label,
    this.prefix,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixStyle: const TextStyle(color: Colors.white),
        filled: true,
        fillColor: const Color(0xFF1A1F35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF10B981), width: 1.5),
        ),
      ),
    );
  }
}