// lib/features/auth/pin_lock_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/providers/shift_provider.dart';
import '../../features/shifts/open_shift_screen.dart';
import '../../core/providers/role_permissions_provider.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/services/audit_service.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final appLockedProvider = StateProvider<bool>((ref) => true);

final inactivityProvider =
    NotifierProvider<InactivityNotifier, void>(InactivityNotifier.new);

class InactivityNotifier extends Notifier<void> {
  @override
  void build() {}
}

// ── Layout helper ─────────────────────────────────────────────────────────────

enum _PinLayout {
  /// Phone portrait  — staff list scrolls above PIN pad (stacked)
  phonePortrait,

  /// Phone landscape — staff list left (compact), PIN right
  phoneLandscape,

  /// Tablet/desktop portrait — staff list top half, PIN bottom half
  tabletPortrait,

  /// Tablet/desktop landscape — staff list left panel, PIN right panel
  tabletLandscape,
}

_PinLayout _pinLayoutOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final w = size.width;
  final h = size.height;
  final portrait = h >= w;

  if (w < 600) return portrait ? _PinLayout.phonePortrait : _PinLayout.phoneLandscape;
  if (portrait) return _PinLayout.tabletPortrait;
  return _PinLayout.tabletLandscape;
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
  bool _showShiftGate = false;
  bool _wasKicked = false;
  Timer? _inactivityTimer;

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    if (ref.read(appLockedProvider)) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) ref.read(appLockedProvider.notifier).state = true;
    });
  }

  Future<void> _handleUnlock() async {
    final staff = _selectedStaff;
    setState(() => _selectedStaff = null);

    // Claim session — kicks any other device watching this staff
    final businessId = ref.read(businessProvider)?.id ?? '';
    if (staff != null && businessId.isNotEmpty) {
      await ref.read(staffSessionServiceProvider).claimSession(
            businessId: businessId,
            staffId: staff.id,
          );
      // Start watching — if another device claims later, lock this device
      ref.read(staffSessionServiceProvider).startWatching(
        staffId: staff.id,
        onKicked: () {
          if (mounted) {
            setState(() => _wasKicked = true);
            ref.read(staffSessionServiceProvider).stopWatching();
            ref.read(activeStaffProvider.notifier).logout();
            // Show kicked message briefly then lock
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() => _wasKicked = false);
                ref.read(appLockedProvider.notifier).state = true;
              }
            });
          }
        },
      );
    }

    final shift = await ref.read(currentShiftProvider.future);
    debugPrint('[ShiftGate] shift after unlock: ${shift?.id} status: ${shift?.status}');
    if (!mounted) return;
    if (shift == null) {
      setState(() => _showShiftGate = true);
    } else {
      ref.read(appLockedProvider.notifier).state = false;
      _resetTimer();
    }
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

          if (_wasKicked)
            Material(
              color: const Color(0xFF0B0E1A),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices_other,
                        color: Color(0xFFE94560), size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Account opened on another device',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This device will lock in a moment...',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha:0.4),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          if (isLocked && !_showShiftGate && !_wasKicked)
            _PinScreen(
              selectedStaff: _selectedStaff,
              onStaffSelected: (s) => setState(() => _selectedStaff = s),
              onUnlocked: _handleUnlock,
            ),
        ],
      ),
    );
  }
}

// ── PIN Screen — layout router ────────────────────────────────────────────────

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

  static const _bg      = Color(0xFF0F1223);

  static const _accent  = Color(0xFFE94560);

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

  Future<void> _verify() async {
    final staff = widget.selectedStaff;
    if (staff == null) return;
    if (staff.checkPin(_pin)) {
      HapticFeedback.lightImpact();
      ref.read(activeStaffProvider.notifier).login(staff);
      ref.read(rolePermissionsProvider.notifier).refresh();
      ref.read(auditServiceProvider).log(
        actionType:  AuditAction.staffLogin,
        description: '${staff.name} logged in (${staff.role.label})',
        metadata:    {'role': staff.role.value},
      );
      // Silently upgrade legacy unsalted PIN to PBKDF2 on first login
      if (staff.needsPinUpgrade) {
        _upgradePinHash(staff, _pin);
      }
      ref.invalidate(currentShiftProvider);
      await ref.read(currentShiftProvider.future);
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  Future<void> _upgradePinHash(StaffMember staff, String pin) async {
    try {
      final salt = StaffMember.generateSalt();
      final newHash = StaffMember.hashPin(pin, salt);
      await Supabase.instance.client
          .from('staff_members')
          .update({'pin_hash': newHash, 'pin_salt': salt})
          .eq('id', staff.id);
      debugPrint('[PIN] Upgraded PIN hash for ${staff.name}');
    } catch (e) {
      // Non-fatal — legacy hash still works until next login
      debugPrint('[PIN] PIN upgrade failed (non-fatal): $e');
    }
  }

  Color _roleColor(StaffRole role) => switch (role) {
        StaffRole.owner   => const Color(0xFFE94560),
        StaffRole.manager => const Color(0xFF4CAF50),
        StaffRole.cashier => const Color(0xFF2196F3),
        StaffRole.kitchen => const Color(0xFFFF9800),
      };

  @override
  Widget build(BuildContext context) {
    final layout = _pinLayoutOf(context);
    final staffAsync = ref.watch(staffListProvider);
    final staffList = staffAsync.asData?.value ?? [];
    final staffStillLoading = staffAsync.isLoading && staffList.isEmpty;
    final selected = widget.selectedStaff;

    final staffPanel = _StaffPanel(
      staffList: staffList,
      staffStillLoading: staffStillLoading,
      selected: selected,
      layout: layout,
      onStaffSelected: (s) {
        widget.onStaffSelected(s);
        setState(() { _pin = ''; _error = false; });
      },
    );

    final pinPanel = _PinPanel(
      selected: selected,
      pin: _pin,
      error: _error,
      layout: layout,
      roleColor: _roleColor,
      onKey: _onKey,
      onDelete: _onDelete,
      onForgotPin: _showForgotPin,
    );

    return Positioned.fill(
      child: Material(
        color: _bg,
        child: SafeArea(
          child: switch (layout) {
            // ── Phone portrait: staff on top, PIN below, scrollable ──
            _PinLayout.phonePortrait => _PhonePortraitLayout(
                staffPanel: staffPanel,
                pinPanel: pinPanel,
              ),

            // ── Phone landscape: staff left (narrow), PIN right ──────
            _PinLayout.phoneLandscape => _SideBySideLayout(
                staffPanel: staffPanel,
                pinPanel: pinPanel,
                staffFlex: 2,
                pinFlex: 3,
                compact: true,
              ),

            // ── Tablet portrait: staff top half, PIN bottom half ─────
            _PinLayout.tabletPortrait => _TabletPortraitLayout(
                staffPanel: staffPanel,
                pinPanel: pinPanel,
              ),

            // ── Tablet/desktop landscape: classic two-panel ──────────
            _PinLayout.tabletLandscape => _SideBySideLayout(
                staffPanel: staffPanel,
                pinPanel: pinPanel,
                staffFlex: 1,
                pinFlex: 1,
                compact: false,
              ),
          },
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
          'A password reset link will be sent to your business '
          'account email address.',
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
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reset email sent.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _PinScreenState._accent,
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

// ── Layout shells ─────────────────────────────────────────────────────────────

/// Phone portrait: single scrollable column, staff then PIN
class _PhonePortraitLayout extends StatelessWidget {
  final Widget staffPanel;
  final Widget pinPanel;
  const _PhonePortraitLayout(
      {required this.staffPanel, required this.pinPanel});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          staffPanel,
          const Divider(color: Colors.white12, height: 1),
          pinPanel,
        ],
      ),
    );
  }
}

/// Tablet portrait: top half staff, bottom half PIN — both scroll independently
class _TabletPortraitLayout extends StatelessWidget {
  final Widget staffPanel;
  final Widget pinPanel;
  const _TabletPortraitLayout(
      {required this.staffPanel, required this.pinPanel});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      children: [
        SizedBox(height: h * 0.42, child: staffPanel),
        const Divider(color: Colors.white12, height: 1),
        Expanded(child: pinPanel),
      ],
    );
  }
}

/// Phone landscape + tablet/desktop landscape: side by side
class _SideBySideLayout extends StatelessWidget {
  final Widget staffPanel;
  final Widget pinPanel;
  final int staffFlex;
  final int pinFlex;
  final bool compact;

  const _SideBySideLayout({
    required this.staffPanel,
    required this.pinPanel,
    required this.staffFlex,
    required this.pinFlex,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: staffFlex,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.white.withValues(alpha:0.06)),
              ),
            ),
            child: staffPanel,
          ),
        ),
        Expanded(flex: pinFlex, child: pinPanel),
      ],
    );
  }
}

// ── Staff panel ───────────────────────────────────────────────────────────────

class _StaffPanel extends StatelessWidget {
  final List<StaffMember> staffList;
  final bool staffStillLoading;
  final StaffMember? selected;
  final _PinLayout layout;
  final ValueChanged<StaffMember> onStaffSelected;

  const _StaffPanel({
    required this.staffList,
    required this.staffStillLoading,
    required this.selected,
    required this.layout,
    required this.onStaffSelected,
  });

  bool get _isPhone =>
      layout == _PinLayout.phonePortrait ||
      layout == _PinLayout.phoneLandscape;
  bool get _isLandscape =>
      layout == _PinLayout.phoneLandscape ||
      layout == _PinLayout.tabletLandscape;

  @override
  Widget build(BuildContext context) {
    final hPad = _isPhone ? 20.0 : 32.0;
    final vPad = _isPhone ? 24.0 : 48.0;
    final titleSize = _isPhone ? 20.0 : 26.0;
    final logoSize = _isPhone ? 38.0 : 48.0;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize:
          _isLandscape ? MainAxisSize.min : MainAxisSize.max,
      children: [
        // Logo
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            color: const Color(0xFFE94560),
            borderRadius:
                BorderRadius.circular(_isPhone ? 10 : 14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE94560).withValues(alpha:0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(Icons.bolt,
              color: Colors.white, size: _isPhone ? 22 : 28),
        ),
        SizedBox(height: _isPhone ? 16 : 24),

        Text(
          "Who's there?",
          style: TextStyle(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select your profile to continue',
          style: TextStyle(
            color: Colors.white.withValues(alpha:0.4),
            fontSize: _isPhone ? 12 : 13,
          ),
        ),
        SizedBox(height: _isPhone ? 20 : 36),

        if (staffList.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: staffStillLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'No staff found.\nPlease contact the owner.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.4),
                      fontSize: 13,
                    ),
                  ),
          )
        else
          // Phone landscape: horizontal scroll row to save vertical space
          layout == _PinLayout.phoneLandscape
              ? _CompactStaffRow(
                  staffList: staffList,
                  selected: selected,
                  onTap: onStaffSelected,
                )
              : Wrap(
                  spacing: 16,
                  runSpacing: _isPhone ? 12 : 20,
                  alignment: WrapAlignment.center,
                  children: staffList
                      .map((s) => _StaffAvatar(
                            staff: s,
                            selected: selected?.id == s.id,
                            compact: _isPhone,
                            onTap: () => onStaffSelected(s),
                          ))
                      .toList(),
                ),
      ],
    );

    if (_isLandscape) {
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(
            horizontal: hPad, vertical: vPad),
        child: content,
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, 16),
      child: content,
    );
  }
}

/// Compact horizontal staff row for phone landscape
class _CompactStaffRow extends StatelessWidget {
  final List<StaffMember> staffList;
  final StaffMember? selected;
  final ValueChanged<StaffMember> onTap;

  const _CompactStaffRow({
    required this.staffList,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: staffList.map((s) {
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StaffAvatar(
              staff: s,
              selected: selected?.id == s.id,
              compact: true,
              onTap: () => onTap(s),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── PIN panel ─────────────────────────────────────────────────────────────────

class _PinPanel extends StatelessWidget {
  final StaffMember? selected;
  final String pin;
  final bool error;
  final _PinLayout layout;
  final Color Function(StaffRole) roleColor;
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;
  final VoidCallback onForgotPin;

  const _PinPanel({
    required this.selected,
    required this.pin,
    required this.error,
    required this.layout,
    required this.roleColor,
    required this.onKey,
    required this.onDelete,
    required this.onForgotPin,
  });

  bool get _isPhone =>
      layout == _PinLayout.phonePortrait ||
      layout == _PinLayout.phoneLandscape;

  @override
  Widget build(BuildContext context) {
    final vPad = _isPhone ? 24.0 : 48.0;
    final hPad = _isPhone ? 20.0 : 32.0;
    // Shrink numpad keys on phone landscape to fit height
    final keySize = layout == _PinLayout.phoneLandscape ? 52.0 : 64.0;
    final keyFontSize = layout == _PinLayout.phoneLandscape ? 18.0 : 22.0;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: selected == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    color: Colors.white.withValues(alpha:0.15),
                    size: _isPhone ? 36 : 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select a profile\nto enter your PIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.25),
                      fontSize: _isPhone ? 13 : 14,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Staff chip
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: _isPhone ? 14 : 20,
                      vertical: _isPhone ? 10 : 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1F35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            roleColor(selected!.role).withValues(alpha:0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: _isPhone ? 14 : 18,
                          backgroundColor:
                              roleColor(selected!.role).withValues(alpha:0.2),
                          child: Text(
                            selected!.name[0].toUpperCase(),
                            style: TextStyle(
                              color: roleColor(selected!.role),
                              fontWeight: FontWeight.w800,
                              fontSize: _isPhone ? 12 : 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected!.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: _isPhone ? 13 : 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              selected!.role.label,
                              style: TextStyle(
                                color: roleColor(selected!.role)
                                    .withValues(alpha:0.8),
                                fontSize: _isPhone ? 10 : 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: _isPhone ? 20 : 28),

                  // PIN dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < pin.length;
                      final dotSize = _isPhone ? 11.0 : 14.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.symmetric(
                            horizontal: _isPhone ? 6 : 8),
                        width: filled ? dotSize + 2 : dotSize,
                        height: filled ? dotSize + 2 : dotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: error
                              ? Colors.red
                              : filled
                                  ? roleColor(selected!.role)
                                  : Colors.white.withValues(alpha:0.15),
                          boxShadow: filled && !error
                              ? [
                                  BoxShadow(
                                    color: roleColor(selected!.role)
                                        .withValues(alpha:0.5),
                                    blurRadius: 8,
                                  )
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),

                  SizedBox(
                    height: _isPhone ? 22 : 28,
                    child: Center(
                      child: error
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  'Incorrect PIN — try again',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontSize: _isPhone ? 11 : 12),
                                ),
                              ],
                            )
                          : Text(
                              'Enter your 4-digit PIN',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha:0.25),
                                fontSize: _isPhone ? 10 : 11,
                              ),
                            ),
                    ),
                  ),

                  SizedBox(height: _isPhone ? 4 : 8),
                  _Numpad(
                    onKey: onKey,
                    onDelete: onDelete,
                    keySize: keySize,
                    fontSize: keyFontSize,
                    spacing: _isPhone ? 6.0 : 10.0,
                  ),
                  SizedBox(height: _isPhone ? 8 : 16),

                  TextButton(
                    onPressed: onForgotPin,
                    child: Text(
                      'Forgot PIN?',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.3),
                        fontSize: _isPhone ? 11 : 12,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Staff Avatar ──────────────────────────────────────────────────────────────

class _StaffAvatar extends StatelessWidget {
  final StaffMember staff;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _StaffAvatar({
    required this.staff,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  static const _roleColors = {
    StaffRole.owner:   Color(0xFFE94560),
    StaffRole.manager: Color(0xFF4CAF50),
    StaffRole.cashier: Color(0xFF2196F3),
    StaffRole.kitchen: Color(0xFFFF9800),
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[staff.role] ?? Colors.grey;
    final radius = compact ? 20.0 : 28.0;
    final fontSize = compact ? 14.0 : 20.0;
    final nameSize = compact ? 10.0 : 11.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: compact ? 56 : 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                          color: color.withValues(alpha:0.4),
                          blurRadius: 12,
                        )
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: radius,
                backgroundColor:
                    color.withValues(alpha:selected ? 0.9 : 0.15),
                child: Text(
                  staff.name[0].toUpperCase(),
                  style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w800,
                    fontSize: fontSize,
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              staff.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha:0.45),
                fontSize: nameSize,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              staff.role.label,
              style: TextStyle(
                color: selected ? color : Colors.transparent,
                fontSize: compact ? 8 : 9,
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
  final double keySize;
  final double fontSize;
  final double spacing;

  const _Numpad({
    required this.onKey,
    required this.onDelete,
    this.keySize = 64,
    this.fontSize = 22,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['',  '0', 'del'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        return Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((k) {
              if (k.isEmpty) return SizedBox(width: keySize);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing * 0.8),
                child: _NumKey(
                  label: k,
                  size: keySize,
                  fontSize: fontSize,
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
  final double size;
  final double fontSize;

  const _NumKey({
    required this.label,
    required this.onTap,
    required this.size,
    required this.fontSize,
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
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed
              ? Colors.white.withValues(alpha:0.18)
              : Colors.white.withValues(alpha:0.07),
          border: Border.all(
            color:
                Colors.white.withValues(alpha:_pressed ? 0.2 : 0.06),
          ),
        ),
        child: Center(
          child: widget.isDelete
              ? Icon(
                  Icons.backspace_outlined,
                  color: Colors.white.withValues(alpha:0.6),
                  size: widget.size * 0.3,
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}