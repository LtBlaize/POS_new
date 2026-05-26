// lib/features/auth/manager_override_dialog.dart
//
// Reusable manager/owner PIN override dialog.
// Shows a PIN pad and verifies against any staff member with
// role >= manager. Returns the authorised StaffMember or null.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/staff.dart';
import '../../core/services/audit_service.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/services/local_db_service.dart';
import '../../shared/widgets/app_colors.dart';
import '../../features/auth/auth_provider.dart';

/// Call this wherever a manager override is needed.
/// Returns the [StaffMember] who approved, or null if cancelled/denied.
///
/// [action] — short description shown in the dialog header, e.g. "Apply Discount"
Future<StaffMember?> requireManagerOverride({
  required BuildContext context,
  required WidgetRef ref,
  String action = 'Authorise Action',
}) {
  return showDialog<StaffMember>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ManagerOverrideDialog(action: action, widgetRef: ref),
  );
}

class _ManagerOverrideDialog extends ConsumerStatefulWidget {
  final String action;
  final WidgetRef widgetRef;

  const _ManagerOverrideDialog({
    required this.action,
    required this.widgetRef,
  });

  @override
  ConsumerState<_ManagerOverrideDialog> createState() =>
      _ManagerOverrideDialogState();
}

class _ManagerOverrideDialogState
    extends ConsumerState<_ManagerOverrideDialog> {
  String _pin = '';
  String? _error;
  bool _checking = false;

  void _onKey(String key) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += key;
      _error = null;
    });
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verify() async {
    if (_pin.length < 4) return;
    setState(() => _checking = true);

    // Find a manager or owner whose PIN matches
    StaffMember? match;

    final local = ref.read(localDbServiceProvider);
    final staffAsync = ref.read(staffListProvider);
    final staffList = staffAsync.asData?.value ?? [];

    // Try in-memory list first (works online and offline)
    try {
      match = staffList.firstWhere(
        (s) =>
            (s.role == StaffRole.owner || s.role == StaffRole.manager) &&
            s.checkPin(_pin),
      );
    } catch (_) {
      match = null;
    }

    // Fallback: local DB (covers edge case where staffList not loaded)
    if (match == null) {
      final businessId = ref.read(profileProvider).asData?.value?.businessId;
      if (businessId != null) {
        final allLocal = await local.getStaff(businessId);
        try {
          match = allLocal.firstWhere(
            (s) =>
                (s.role == StaffRole.owner || s.role == StaffRole.manager) &&
                s.checkPin(_pin),
          );
        } catch (_) {
          match = null;
        }
      }
    }

    if (!mounted) return;

    if (match != null) {
      HapticFeedback.mediumImpact();
      // Audit the override approval
      await ref.read(auditServiceProvider).log(
        actionType:   AuditAction.managerOverride,
        description:  'Manager override approved for: ${widget.action}',
        authorisedBy: match,
        metadata:     {'action': widget.action},
      );
      if (mounted) Navigator.of(context).pop(match);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _pin = '';
        _error = 'Incorrect PIN or insufficient role.';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 360,
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
            // ── Header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.warning.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.admin_panel_settings_outlined,
                        color: AppColors.warning, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Manager Override',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text(
                          widget.action,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _checking
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.close,
                          color: Colors.white.withOpacity(0.4),
                          size: 16),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                children: [
                  Text(
                    'Enter Manager or Owner PIN',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // PIN dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (i) {
                      final filled = i < _pin.length;
                      return Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 5),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? (_error != null
                                  ? AppColors.danger
                                  : AppColors.warning)
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

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 11)),
                  ],

                  const SizedBox(height: 18),

                  // Numpad — reuse same layout as void dialog
                  _buildNumpad(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
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
                          onTap: _checking ? null : () => _onKey(k),
                        ))
                    .toList(),
              ),
            )),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PinKey(
                label: '⌫',
                onTap: _checking ? null : _onDelete,
                secondary: true),
            _PinKey(
                label: '0',
                onTap: _checking ? null : () => _onKey('0')),
            _PinKey(
              label: _checking ? '…' : '✓',
              onTap: (_pin.length >= 4 && !_checking) ? _verify : null,
              primary: true,
              disabled: _pin.length < 4 || _checking,
            ),
          ],
        ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
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
    if (disabled || onTap == null) {
      bg = Colors.white.withOpacity(0.04);
      fg = Colors.white.withOpacity(0.2);
    } else if (primary) {
      bg = AppColors.warning.withOpacity(0.15);
      fg = AppColors.warning;
    } else if (secondary) {
      bg = Colors.white.withOpacity(0.06);
      fg = Colors.white.withOpacity(0.5);
    } else {
      bg = Colors.white.withOpacity(0.07);
      fg = Colors.white;
    }

    return GestureDetector(
      onTap: onTap,
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