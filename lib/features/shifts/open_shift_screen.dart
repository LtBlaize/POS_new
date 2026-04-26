// lib/features/shifts/open_shift_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/shift_provider.dart';
import '../../core/providers/staff_provider.dart'; // ← ADD

class OpenShiftScreen extends ConsumerStatefulWidget {
  final VoidCallback onShiftOpened;

  const OpenShiftScreen({super.key, required this.onShiftOpened});

  @override
  ConsumerState<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends ConsumerState<OpenShiftScreen> {
  final _cashCtrl = TextEditingController(text: '0.00');
  bool _loading = false;
  String? _error;

  // Quick-add denomination buttons (PH peso)
  static const _denoms = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0];

  static const _bg = Color(0xFF0B0E1A);
  static const _card = Color(0xFF141827);
  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);
  static const _dim = Color(0xFF6B7280);

  double get _currentAmount {
    return double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
  }

  void _addDenom(double value) {
    final current = _currentAmount;
    final newVal = current + value;
    setState(() {
      _cashCtrl.text = newVal.toStringAsFixed(2);
      _error = null;
    });
  }

  void _reset() {
    setState(() {
      _cashCtrl.text = '0.00';
      _error = null;
    });
  }

  Future<void> _openShift() async {
    final amount = _currentAmount;
    if (amount < 0) {
      setState(() => _error = 'Opening cash cannot be negative');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(currentShiftProvider.notifier)
          .openShift(openingCash: amount);
      if (mounted) widget.onShiftOpened();
    } catch (e) {
      setState(() {
        _error = 'Failed to open shift. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(activeStaffProvider);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────
                _buildHeader(staff?.name ?? 'Cashier', now),
                const SizedBox(height: 32),

                // ── Cash input card ──────────────────────────────────────
                _buildCashInputCard(),
                const SizedBox(height: 16),

                // ── Denomination quick-add ───────────────────────────────
                _buildDenomGrid(),
                const SizedBox(height: 8),

                // Reset
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset to ₱0.00'),
                  style: TextButton.styleFrom(foregroundColor: _dim),
                ),
                const SizedBox(height: 24),

                // ── Error ────────────────────────────────────────────────
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: _accent.withOpacity(0.3)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: _accent, fontSize: 13)),
                  ),

                // ── Open Shift button ────────────────────────────────────
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _openShift,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(
                                  Icons.lock_open_rounded,
                                  size: 20),
                              const SizedBox(width: 10),
                              Text(
                                'Open Shift  ·  ₱${NumberFormat('#,##0.00').format(_currentAmount)}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'This amount is your starting cash fund\nand will be included in the shift report.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _dim, fontSize: 12, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name, DateTime now) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Store icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: _accent, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Start of Shift',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 6),
          Text(
            'Welcome, $name',
            style: const TextStyle(
                color: Color(0xFF10B981),
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, MMMM d · h:mm a').format(now),
            style: TextStyle(
                color: Colors.white.withOpacity(0.35), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCashInputCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OPENING CASH FUND',
            style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '₱',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 28,
                    fontWeight: FontWeight.w300),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cashCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[\d.]')),
                  ],
                  onChanged: (_) => setState(() => _error = null),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0.00',
                    hintStyle: TextStyle(
                        color: Color(0xFF374151), fontSize: 36),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 4),
          Text(
            'Tap bills below to add quickly, or type manually',
            style: TextStyle(
                color: Colors.white.withOpacity(0.25), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildDenomGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: _denoms
          .map((d) => _DenomButton(
                value: d,
                onTap: () => _addDenom(d),
              ))
          .toList(),
    );
  }
}

class _DenomButton extends StatelessWidget {
  final double value;
  final VoidCallback onTap;

  static const _surface = Color(0xFF1A1F35);

  const _DenomButton({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Center(
          child: Text(
            '+₱${value.toInt()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}