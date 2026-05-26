// lib/features/orders/widgets/void_item_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/models/staff.dart';
import '../../../core/models/void_record.dart';
import '../../../core/providers/order_provider.dart';
import '../../../core/providers/staff_provider.dart';
import '../../../shared/widgets/app_colors.dart';
import '../../../core/services/audit_service.dart';

// ── Result returned to caller ─────────────────────────────────────────────────

class VoidItemResult {
  final VoidRecord record;
  const VoidItemResult(this.record);
}

// ── Public entry point ────────────────────────────────────────────────────────

/// Shows the void-item dialog.
/// Returns [VoidItemResult] on success, null if cancelled / denied.
///
/// Role check: only [StaffRole.owner] or [StaffRole.manager] may proceed.
/// The active staff's PIN is re-verified inside the dialog.
Future<VoidItemResult?> showVoidItemDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String orderId,
  required String businessId,
  required CartItem item,
}) {
  // Guard: check role before even opening the dialog
  final active = ref.read(activeStaffProvider);
  if (active == null) {
    ScaffoldMessenger.of(context).showSnackBar(_errorSnack(
      'No staff session active. Please log in.',
    ));
    return Future.value(null);
  }

  final role = active.role;
  if (role != StaffRole.owner && role != StaffRole.manager) {
    ScaffoldMessenger.of(context).showSnackBar(_errorSnack(
      'Only a Manager or Owner can void items.',
    ));
    return Future.value(null);
  }

  return showDialog<VoidItemResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VoidItemDialog(
      orderId: orderId,
      businessId: businessId,
      item: item,
      authorisedStaff: active,
    ),
  );
}

SnackBar _errorSnack(String msg) => SnackBar(
      content: Row(children: [
        const Icon(Icons.lock_outline, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    );

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _VoidItemDialog extends ConsumerStatefulWidget {
  final String orderId;
  final String businessId;
  final CartItem item;
  final StaffMember authorisedStaff;

  const _VoidItemDialog({
    required this.orderId,
    required this.businessId,
    required this.item,
    required this.authorisedStaff,
  });

  @override
  ConsumerState<_VoidItemDialog> createState() => _VoidItemDialogState();
}

// Two-step: 1) PIN verification  2) Reason selection
enum _Step { pin, reason }

class _VoidItemDialogState extends ConsumerState<_VoidItemDialog> {
  _Step _step = _Step.pin;

  // PIN step
  String _enteredPin = '';
  String? _pinError;

  // Reason step
  String? _selectedReason;
  bool _voiding = false;

  // ── PIN step ────────────────────────────────────────────────────────────────

  void _onPinKey(String key) {
    if (_enteredPin.length >= 6) return;
    setState(() {
      _enteredPin += key;
      _pinError = null;
    });
  }

  void _onPinDelete() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _pinError = null;
    });
  }

  void _verifyPin() {
    final ok =
        widget.authorisedStaff.checkPin(_enteredPin);
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() {
        _enteredPin = '';
        _pinError = 'Incorrect PIN. Try again.';
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _step = _Step.reason);
  }

  // ── Void execution ──────────────────────────────────────────────────────────

  Future<void> _confirmVoid() async {
    if (_selectedReason == null) return;
    setState(() => _voiding = true);

    try {
      final record = await ref.read(orderServiceProvider).voidOrderItem(
            orderId: widget.orderId,
            productId: widget.item.product.id,
            productName: widget.item.product.name,
            unitPrice: widget.item.product.price,
            quantity: widget.item.quantity,
            reason: _selectedReason!,
            voidedByStaffId: widget.authorisedStaff.id,
            voidedByStaffName: widget.authorisedStaff.name,
            businessId: widget.businessId,
            trackInventory: widget.item.product.trackInventory,
            currentStock: widget.item.product.stockQuantity,
          );

      // Audit log
      await ref.read(auditServiceProvider).log(
        actionType:  AuditAction.voidItem,
        entityType:  'order_item',
        entityId:    widget.orderId,
        description: 'Voided ${widget.item.quantity}× ${widget.item.product.name}'
            ' — reason: $_selectedReason',
        authorisedBy: widget.authorisedStaff,
        metadata: {
          'product_name': widget.item.product.name,
          'quantity':     widget.item.quantity,
          'unit_price':   widget.item.product.price,
          'reason':       _selectedReason,
          'order_id':     widget.orderId,
        },
      );

      // Invalidate so the orders screen refreshes
      ref.invalidate(ordersStreamProvider);

      if (mounted) {
        Navigator.of(context).pop(VoidItemResult(record));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _voiding = false);
        ScaffoldMessenger.of(context).showSnackBar(_errorSnack('Void failed: $e'));
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildItemPreview(),
            const Divider(color: Color(0xFF2A2A3E), height: 1),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _step == _Step.pin
                  ? _buildPinStep()
                  : _buildReasonStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Icon(Icons.remove_circle_outline,
                color: AppColors.danger, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Void Item',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Text(
                _step == _Step.pin
                    ? 'Manager / Owner PIN required'
                    : 'Select a void reason',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: _voiding ? null : () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.close,
                  color: Colors.white.withOpacity(0.4), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemPreview() {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text('${item.quantity}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.product.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          Text(
            '₱${item.total.toStringAsFixed(2)}',
            style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── PIN step ────────────────────────────────────────────────────────────────

  Widget _buildPinStep() {
    return Padding(
      key: const ValueKey('pin'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Text(
            'Enter PIN for ${widget.authorisedStaff.name}',
            style: TextStyle(
                color: Colors.white.withOpacity(0.55), fontSize: 12),
          ),
          const SizedBox(height: 16),
          // PIN dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = i < _enteredPin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? (_pinError != null
                          ? AppColors.danger
                          : AppColors.primary)
                      : Colors.white.withOpacity(0.12),
                  border: Border.all(
                    color: filled
                        ? Colors.transparent
                        : Colors.white.withOpacity(0.2),
                  ),
                ),
              );
            }),
          ),
          if (_pinError != null) ...[
            const SizedBox(height: 10),
            Text(_pinError!,
                style:
                    TextStyle(color: AppColors.danger, fontSize: 11)),
          ],
          const SizedBox(height: 18),
          // Numpad
          _PinNumpad(
            onKey: _onPinKey,
            onDelete: _onPinDelete,
            onConfirm:
                _enteredPin.length >= 4 ? _verifyPin : null,
          ),
        ],
      ),
    );
  }

  // ── Reason step ─────────────────────────────────────────────────────────────

  Widget _buildReasonStep() {
    return Padding(
      key: const ValueKey('reason'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...kVoidReasons.map((r) => _ReasonTile(
                label: r,
                selected: _selectedReason == r,
                onTap: _voiding
                    ? null
                    : () => setState(() => _selectedReason = r),
              )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: (_selectedReason != null && !_voiding)
                  ? _confirmVoid
                  : null,
              icon: _voiding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.remove_circle_outline, size: 18),
              label: Text(
                _voiding ? 'Voiding…' : 'Confirm Void',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.danger.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reason tile ───────────────────────────────────────────────────────────────

class _ReasonTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonTile({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.danger.withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.danger.withOpacity(0.45)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w400)),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: AppColors.danger, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── PIN numpad ────────────────────────────────────────────────────────────────

class _PinNumpad extends StatelessWidget {
  final void Function(String) onKey;
  final VoidCallback onDelete;
  final VoidCallback? onConfirm;

  const _PinNumpad({
    required this.onKey,
    required this.onDelete,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        ...keys.map((row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row
                    .map((k) => _PinKey(
                          label: k,
                          onTap: () => onKey(k),
                        ))
                    .toList(),
              ),
            )),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PinKey(label: '⌫', onTap: onDelete, secondary: true),
            _PinKey(label: '0', onTap: () => onKey('0')),
            _PinKey(
              label: '✓',
              onTap: onConfirm ?? () {},
              disabled: onConfirm == null,
              primary: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool secondary;
  final bool primary;
  final bool disabled;

  const _PinKey({
    required this.label,
    required this.onTap,
    this.secondary = false,
    this.primary = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (disabled) {
      bg = Colors.white.withOpacity(0.04);
      fg = Colors.white.withOpacity(0.2);
    } else if (primary) {
      bg = AppColors.primary.withOpacity(0.15);
      fg = AppColors.primary;
    } else if (secondary) {
      bg = Colors.white.withOpacity(0.06);
      fg = Colors.white.withOpacity(0.5);
    } else {
      bg = Colors.white.withOpacity(0.07);
      fg = Colors.white;
    }

    return GestureDetector(
      onTap: disabled ? null : () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 72,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: fg,
                  fontSize: label.length == 1 ? 20 : 16,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}