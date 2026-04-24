// lib/features/credits/widgets/add_credit_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/credit.dart';
import '../../../core/providers/credit_provider.dart';

/// Result returned when user confirms utang at checkout
class AddCreditResult {
  final CreditCustomer customer;
  const AddCreditResult(this.customer);
}

class AddCreditDialog extends ConsumerStatefulWidget {
  final double amount;
  final String? orderId;

  const AddCreditDialog({
    super.key,
    required this.amount,
    this.orderId,
  });

  @override
  ConsumerState<AddCreditDialog> createState() => _AddCreditDialogState();
}

class _AddCreditDialogState extends ConsumerState<AddCreditDialog> {
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  bool _loading = false;
  String? _error;
  CreditCustomer? _selected;
  bool _showDropdown = false;

  static const _bg = Color(0xFF0F1223);
  static const _card = Color(0xFF1A1F35);
  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<CreditCustomer> _getFiltered() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final all = ref.read(creditCustomersProvider).value ?? [];
    if (query.isEmpty) return all;
    return all
        .where((c) =>
            c.name.toLowerCase().contains(query) ||
            c.phone.contains(query))
        .toList();
  }

  void _pickCustomer(CreditCustomer c) {
    setState(() {
      _selected = c;
      _searchCtrl.text = c.name;
      _nameCtrl.text = c.name;
      _phoneCtrl.text = c.phone;
      _showDropdown = false;
      _error = null;
    });
    _searchFocus.unfocus();
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _searchCtrl.clear();
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _showDropdown = false;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Name and phone are required');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifier = ref.read(creditCustomersProvider.notifier);
      final customer = await notifier.findOrCreate(name: name, phone: phone);
      await notifier.addCredit(
        customerId: customer.id,
        amount: widget.amount,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        orderId: widget.orderId,
      );
      if (mounted) Navigator.pop(context, AddCreditResult(customer));
    } catch (e) {
      setState(() {
        _error = 'Something went wrong';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFiltered();
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Fixed header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.receipt_long_outlined,
                            color: _accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text('Record Utang',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accent.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount to Credit',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 13)),
                        Text('₱${widget.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: _accent,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable middle ─────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Search Customer',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),

                    if (_selected != null)
                      _SelectedChip(
                        customer: _selected!,
                        onClear: _clearSelection,
                      )
                    else
                      Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            onChanged: (v) => setState(
                                () => _showDropdown = v.isNotEmpty),
                            onTap: () =>
                                setState(() => _showDropdown = true),
                            decoration: InputDecoration(
                              hintText: 'Search by name or phone…',
                              hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 13),
                              prefixIcon: Icon(Icons.search,
                                  color: Colors.white.withOpacity(0.3),
                                  size: 18),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.close,
                                          color: Colors.white.withOpacity(0.3),
                                          size: 16),
                                      onPressed: () =>
                                          setState(() => _searchCtrl.clear()),
                                    )
                                  : null,
                              filled: true,
                              fillColor: _card,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: _accent, width: 1.5),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),

                          if (_showDropdown && filtered.isNotEmpty)
                            Container(
                              constraints:
                                  const BoxConstraints(maxHeight: 180),
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: _card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.08)),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: Colors.white.withOpacity(0.06)),
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  return InkWell(
                                    onTap: () => _pickCustomer(c),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                _accent.withOpacity(0.15),
                                            child: Text(
                                              c.name[0].toUpperCase(),
                                              style: const TextStyle(
                                                  color: _accent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(c.name,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                Text(c.phone,
                                                    style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.35),
                                                        fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          if (c.totalOwed > 0)
                                            Text(
                                              '₱${c.totalOwed.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  color: _accent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700),
                                            )
                                          else
                                            const Icon(Icons.check_circle,
                                                color: _green, size: 14),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                          if (_showDropdown &&
                              filtered.isEmpty &&
                              _searchCtrl.text.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _card,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'No customer found — fill in below to create new',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.3),
                                      fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),

                    const SizedBox(height: 14),

                    if (_selected == null) ...[
                      const Text('Or enter new customer',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _Field(
                        controller: _phoneCtrl,
                        label: 'Phone Number',
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        controller: _nameCtrl,
                        label: 'Customer Name',
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 10),
                    ],

                    _Field(
                      controller: _noteCtrl,
                      label: 'Note (optional)',
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(
                              color: _accent, fontSize: 12)),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Fixed bottom buttons — always visible ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm Utang',
                              style:
                                  TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selected customer chip ────────────────────────────────────────────────────

class _SelectedChip extends StatelessWidget {
  final CreditCustomer customer;
  final VoidCallback onClear;

  const _SelectedChip({required this.customer, required this.onClear});

  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _accent.withOpacity(0.15),
            child: Text(
              customer.name[0].toUpperCase(),
              style: const TextStyle(
                  color: _accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(customer.phone,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11)),
              ],
            ),
          ),
          if (customer.totalOwed > 0) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Current balance',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 10)),
                Text('₱${customer.totalOwed.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ] else
            const Icon(Icons.check_circle, color: _green, size: 16),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClear,
            icon: Icon(Icons.close,
                color: Colors.white.withOpacity(0.3), size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Text field ────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.label,
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
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        filled: true,
        fillColor: const Color(0xFF1A1F35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5),
        ),
      ),
    );
  }
}