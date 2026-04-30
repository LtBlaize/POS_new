import 'package:flutter/material.dart';
import 'checkout_theme.dart';

// ── Quick amount row ──────────────────────────────────────────────────────────

class QuickAmountRow extends StatelessWidget {
  final double subtotal;
  final bool isBusy;
  final ValueChanged<double> onSelect;

  const QuickAmountRow({
    super.key,
    required this.subtotal,
    required this.isBusy,
    required this.onSelect,
  });

  List<double> get _amounts {
    final amounts = <double>[];
    const niceBills = [20, 50, 100, 200, 500, 1000];
    for (final b in niceBills) {
      final rounded = (subtotal / b).ceil() * b.toDouble();
      if (!amounts.contains(rounded) && rounded >= subtotal) {
        amounts.add(rounded);
        if (amounts.length == 4) break;
      }
    }
    return amounts;
  }

  @override
  Widget build(BuildContext context) {
    final amounts = _amounts;
    if (amounts.isEmpty) return const SizedBox.shrink();
    return Row(
      children: amounts
          .map((v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: isBusy ? null : () => onSelect(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: CheckoutTheme.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CheckoutTheme.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '₱${v.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: CheckoutTheme.textHigh,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

// ── Numpad ────────────────────────────────────────────────────────────────────

class Numpad extends StatelessWidget {
  final ValueChanged<String>? onTap;
  const Numpad({super.key, required this.onTap});

  static const _keys = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: row.map((k) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: NumpadKey(
                    label: k,
                    isBackspace: k == '⌫',
                    onTap: onTap == null ? null : () => onTap!(k),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// ── Numpad key ────────────────────────────────────────────────────────────────

class NumpadKey extends StatefulWidget {
  final String label;
  final bool isBackspace;
  final VoidCallback? onTap;

  const NumpadKey({
    super.key,
    required this.label,
    required this.isBackspace,
    required this.onTap,
  });

  @override
  State<NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<NumpadKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (widget.onTap == null) return;
    _ac.forward();
    await Future.delayed(const Duration(milliseconds: 80));
    _ac.reverse();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _press,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: widget.isBackspace ? CheckoutTheme.roseDim : CheckoutTheme.elevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isBackspace
                  ? CheckoutTheme.rose.withOpacity(0.25)
                  : CheckoutTheme.border,
            ),
          ),
          alignment: Alignment.center,
          child: widget.isBackspace
              ? const Icon(Icons.backspace_outlined, color: CheckoutTheme.rose, size: 18)
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: CheckoutTheme.textHigh,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}