// lib/features/auth/otp_verification_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'business_type_screen.dart';
import 'register_screen.dart';
import 'widgets/auth_theme.dart';
import 'widgets/auth_components.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;
  const OtpVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends ConsumerState<OtpVerificationScreen> {
  // 6 individual controllers + focus nodes for each digit box
  final List<TextEditingController> _ctrlList =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusList =
      List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String? _error;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    for (final c in _ctrlList) {
      c.dispose();
    }
    for (final f in _focusList) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Cooldown timer so user can't spam resend ──────────────────────────────
  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown--);
      return _resendCooldown > 0;
    });
  }

  String get _otp => _ctrlList.map((c) => c.text).join();

  // ── Verify ────────────────────────────────────────────────────────────────
  Future<void> _verify() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter all 6 digits.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).verifyRegistrationOtp(
            email: widget.email,
            otp: _otp,
          );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BusinessTypeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e.toString());
          _isLoading = false;
        });
        // Clear boxes on wrong code
        for (final c in _ctrlList) {
          c.clear();
        }
        _focusList.first.requestFocus();
      }
    }
  }

  // ── Resend ────────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;
    setState(() => _isResending = true);
    try {
      await ref
          .read(authServiceProvider)
          .resendOtp(email: widget.email);
      if (mounted) {
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code resent to ${widget.email}'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not resend code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('invalid') || raw.contains('expired') || raw.contains('Token')) {
      return 'Invalid or expired code. Check your email and try again.';
    }
    if (raw.contains('network')) return 'Network error. Check your connection.';
    return 'Verification failed. Please try again.';
  }

  String get _maskedEmail {
    final parts = widget.email.split('@');
    if (parts.length != 2) return widget.email;
    final local = parts[0];
    final keep = local.length <= 3 ? 1 : 3;
    return '${local.substring(0, keep)}***@${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(pendingUserIdProvider.notifier).state = null;
      },
      child: AuthScaffold(
        maxWidth: 520,
        onBack: () => Navigator.pop(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthStepper(current: 2, label: 'Email verification'),
            const SizedBox(height: 24),

            AuthInfoBanner(
              icon: Icons.mail_outline_rounded,
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: 14,
                      color: AuthColors.textSecondary,
                      height: 1.4),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to '),
                    TextSpan(
                      text: _maskedEmail,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AuthColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _OtpBox(
                      controller: _ctrlList[i],
                      focusNode: _focusList[i],
                      hasError: _error != null,
                      onChanged: (val) {
                        if (val.length == 1 && i < 5) {
                          _focusList[i + 1].requestFocus();
                        }
                        // Auto-submit when last digit entered (unchanged)
                        if (i == 5 && val.length == 1) {
                          _verify();
                        }
                        setState(() => _error = null);
                      },
                      onBackspace: () {
                        if (_ctrlList[i].text.isEmpty && i > 0) {
                          _ctrlList[i - 1].clear();
                          _focusList[i - 1].requestFocus();
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),

            AuthErrorSlot(_error),
            const SizedBox(height: 24),

            AuthButton(
              label: _isLoading ? 'Verifying…' : 'Verify Email',
              icon: Icons.verified_rounded,
              loading: _isLoading,
              onPressed: _otp.length < 6 ? null : _verify,
            ),
            const SizedBox(height: 16),

            Center(
              child: _isResending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AuthColors.accentLight))
                  : Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text("Didn't receive it?",
                            style: AuthText.subtitle),
                        TextButton(
                          onPressed: _resendCooldown > 0 ? null : _resend,
                          style: TextButton.styleFrom(
                            foregroundColor: AuthColors.accentLight,
                            disabledForegroundColor: AuthColors.textMuted,
                          ),
                          child: Text(_resendCooldown > 0
                              ? 'Resend in ${_resendCooldown}s'
                              : 'Resend code'),
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

// ── Single OTP digit box ─────────────────────────────────────────────────────
class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;
  final bool hasError;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    // Focus (not KeyboardListener + new FocusNode() per build) — same
    // backspace behaviour, without leaking a FocusNode on every rebuild.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            controller.text.isEmpty) {
          onBackspace();
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final borderColor = hasError
              ? AuthColors.error
              : focused
                  ? AuthColors.accentLight
                  : AuthColors.border;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AuthColors.field,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: borderColor, width: (focused || hasError) ? 1.5 : 1),
              boxShadow: (focused && !hasError)
                  ? [
                      BoxShadow(
                        color: AuthColors.accentLight.withValues(alpha: 0.35),
                        blurRadius: 10,
                      )
                    ]
                  : null,
            ),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              cursorColor: AuthColors.accentLight,
              keyboardAppearance: Brightness.dark,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AuthColors.textPrimary),
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          );
        },
      ),
    );
  }
}