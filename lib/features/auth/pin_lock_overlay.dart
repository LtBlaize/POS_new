import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/providers/shift_provider.dart';   // ← ADD
import '../../features/shifts/open_shift_screen.dart'; // ← ADD
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

// ── Providers ─────────────────────────────────────────────────────────────────
final appLockedProvider = StateProvider<bool>((ref) => true);

final inactivityProvider =
    NotifierProvider<InactivityNotifier, void>(InactivityNotifier.new);

class InactivityNotifier extends Notifier<void> {
  @override
  void build() {}
}

// ── PinLockOverlay ────────────────────────────────────────────────────────────
class PinLockOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const PinLockOverlay({super.key, required this.child});

  @override
  ConsumerState<PinLockOverlay> createState() => _PinLockOverlayState();
}

class _PinLockOverlayState extends ConsumerState<PinLockOverlay> {
  StaffMember? _selectedStaff;
   bool _showShiftGate = false;  // ← ADD
  Timer? _inactivityTimer; // ← ADD

  @override
  void dispose() {
    _inactivityTimer?.cancel(); // ← ADD
    super.dispose();
  }

  void _resetTimer() {
    if (ref.read(appLockedProvider)) return;
    _inactivityTimer?.cancel(); // ← cancel previous timer
    _inactivityTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) ref.read(appLockedProvider.notifier).state = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = ref.watch(appLockedProvider);

    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,

          // ── Shift gate (on top of everything, before POS is visible) ──
          if (_showShiftGate)
            Material(
              color: const Color(0xFF0B0E1A),
              child: OpenShiftScreen(
                onShiftOpened: () {
                  setState(() => _showShiftGate = false);
                  ref.read(appLockedProvider.notifier).state = false;
                  _resetTimer();
                },
              ),
            ),

          // ── PIN lock ──────────────────────────────────────────────────
          if (isLocked && !_showShiftGate)
            _PinScreen(
              selectedStaff: _selectedStaff,
              onStaffSelected: (s) => setState(() => _selectedStaff = s),
              onUnlocked: _handleUnlock,  // ← changed
            ),
        ],
      ),
    );
  }

  Future<void> _handleUnlock() async {  // ← ADD this method
    setState(() => _selectedStaff = null);

    // Check if this staff member has an open shift
    final shift = await ref.read(currentShiftProvider.future);

    if (!mounted) return;

    if (shift == null) {
      // No open shift → show shift gate before unlocking
      setState(() => _showShiftGate = true);
    } else {
      // Already has an open shift → unlock normally
      ref.read(appLockedProvider.notifier).state = false;
      _resetTimer();
    }
  }
}

  


// ── PIN Screen ────────────────────────────────────────────────────────────────
class _PinScreen extends ConsumerStatefulWidget {
  final StaffMember? selectedStaff;
  final ValueChanged<StaffMember> onStaffSelected;
  final VoidCallback onUnlocked;

  const _PinScreen({
    required this.selectedStaff,
    required this.onStaffSelected,
    required this.onUnlocked,
  });

  @override
  ConsumerState<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<_PinScreen> {
  String _pin = '';
  bool _error = false;

  static const _bg = Color(0xFF0F1223);
  static const _surface = Color(0xFF1A1F35);
  static const _accent = Color(0xFFE94560);

  void _onKey(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = false;
    });
    if (_pin.length == 4) _verify();
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _verify() {
    final staff = widget.selectedStaff;
    if (staff == null) return;
    if (staff.checkPin(_pin)) {
      HapticFeedback.lightImpact();
      ref.read(activeStaffProvider.notifier).login(staff);
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  Color _roleColor(StaffRole role) => switch (role) {
        StaffRole.owner => const Color(0xFFE94560),
        StaffRole.manager => const Color(0xFF4CAF50),
        StaffRole.cashier => const Color(0xFF2196F3),
        StaffRole.kitchen => const Color(0xFFFF9800),
      };

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final staffList = staffAsync.asData?.value ?? [];
    final selected = widget.selectedStaff;

    return Positioned.fill(
      child: Material(
        color: _bg,
        child: SafeArea(
          child: Row(
            children: [
              // ── LEFT: Who's there? + staff avatars ───────────────────
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withOpacity(0.06),
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        vertical: 48, horizontal: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.bolt,
                              color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          "Who's there?",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Select your profile to continue',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Staff avatars
                        if (staffList.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'No staff found.\nPlease contact the owner.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 16,
                            runSpacing: 20,
                            children: staffList
                                .map((s) => _StaffAvatar(
                                      staff: s,
                                      selected: selected?.id == s.id,
                                      onTap: () {
                                        widget.onStaffSelected(s);
                                        setState(() {
                                          _pin = '';
                                          _error = false;
                                        });
                                      },
                                    ))
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── RIGHT: PIN entry ──────────────────────────────────────
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        vertical: 48, horizontal: 32),
                    child: selected == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                color: Colors.white.withOpacity(0.15),
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Select a profile\nto enter your PIN',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.25),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Selected staff card
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _roleColor(selected.role)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: _roleColor(selected.role)
                                          .withOpacity(0.2),
                                      child: Text(
                                        selected.name[0].toUpperCase(),
                                        style: TextStyle(
                                          color: _roleColor(selected.role),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          selected.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          selected.role.label,
                                          style: TextStyle(
                                            color: _roleColor(selected.role)
                                                .withOpacity(0.8),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // PIN dots
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(4, (i) {
                                  final filled = i < _pin.length;
                                  return AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    width: filled ? 14 : 12,
                                    height: filled ? 14 : 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _error
                                          ? Colors.red
                                          : filled
                                              ? _roleColor(selected.role)
                                              : Colors.white.withOpacity(0.15),
                                      boxShadow: filled && !_error
                                          ? [
                                              BoxShadow(
                                                color: _roleColor(selected.role)
                                                    .withOpacity(0.5),
                                                blurRadius: 8,
                                              )
                                            ]
                                          : null,
                                    ),
                                  );
                                }),
                              ),

                              // Error / hint — fixed height
                              SizedBox(
                                height: 28,
                                child: Center(
                                  child: _error
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(Icons.error_outline,
                                                color: Colors.red, size: 13),
                                            SizedBox(width: 4),
                                            Text(
                                              'Incorrect PIN — try again',
                                              style: TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 12),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          'Enter your 4-digit PIN',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.25),
                                            fontSize: 11,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Numpad
                              _Numpad(onKey: _onKey, onDelete: _onDelete),

                              const SizedBox(height: 16),

                              TextButton(
                                onPressed: _showForgotPin,
                                child: Text(
                                  'Forgot PIN?',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showForgotPin() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset PIN',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'A password reset link will be sent to the owner\'s registered email address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Supabase.instance.client.auth.resetPasswordForEmail(
                Supabase.instance.client.auth.currentUser?.email ?? '',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reset email sent to owner.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Send Reset Email'),
          ),
        ],
      ),
    );
  }
}

// ── Staff Avatar ──────────────────────────────────────────────────────────────
class _StaffAvatar extends StatelessWidget {
  final StaffMember staff;
  final bool selected;
  final VoidCallback onTap;

  const _StaffAvatar({
    required this.staff,
    required this.selected,
    required this.onTap,
  });

  static const _roleColors = {
    StaffRole.owner: Color(0xFFE94560),
    StaffRole.manager: Color(0xFF4CAF50),
    StaffRole.cashier: Color(0xFF2196F3),
    StaffRole.kitchen: Color(0xFFFF9800),
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[staff.role] ?? Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 12,
                        )
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(selected ? 0.9 : 0.15),
                child: Text(
                  staff.name[0].toUpperCase(),
                  style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              staff.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    selected ? Colors.white : Colors.white.withOpacity(0.45),
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              staff.role.label,
              style: TextStyle(
                color: selected ? color : Colors.transparent,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Numpad ────────────────────────────────────────────────────────────────────
class _Numpad extends StatelessWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;

  const _Numpad({required this.onKey, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((k) {
              if (k.isEmpty) return const SizedBox(width: 72);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _NumKey(
                  label: k,
                  onTap: k == 'del' ? onDelete : () => onKey(k),
                  isDelete: k == 'del',
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _NumKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDelete;

  const _NumKey({
    required this.label,
    required this.onTap,
    this.isDelete = false,
  });

  @override
  State<_NumKey> createState() => _NumKeyState();
}

class _NumKeyState extends State<_NumKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.07),
          border: Border.all(
            color: Colors.white.withOpacity(_pressed ? 0.2 : 0.06),
          ),
        ),
        child: Center(
          child: widget.isDelete
              ? Icon(
                  Icons.backspace_outlined,
                  color: Colors.white.withOpacity(0.6),
                  size: 20,
                )
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}