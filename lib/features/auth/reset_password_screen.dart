import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'widgets/auth_text_field.dart';
import '../../shared/widgets/app_colors.dart';
import '../../shared/widgets/app_button.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _codeVerified = false; // code is single-use, so don't re-verify on retry
  String? _error;

  @override
  void initState() {
    super.initState();
    RecoveryGuard.isRecovering = true;
  }

  @override
  void dispose() {
    RecoveryGuard.isRecovering = false;
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });

    final auth = ref.read(authServiceProvider);
    try {
      if (!_codeVerified) {
        await auth.verifyRecoveryCode(
          email: widget.email,
          code: _codeCtrl.text.trim(),
        );
        _codeVerified = true;
      }
      await auth.updatePassword(newPassword: _passCtrl.text);
      await auth.logout(); // force a clean login with the new password

      if (!mounted) return;
      RecoveryGuard.isRecovering = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Please log in.')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      setState(() => _error = msg.contains('expired') || msg.contains('invalid')
          ? 'Code is invalid or expired. Go back and request a new one.'
          : 'Could not update password. ${_codeVerified ? "Try a different password." : "Try again."}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Text('Reset Password',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text('Enter the 6-digit code we sent to\n${widget.email}',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 32),
                if (!_codeVerified) ...[
                  AuthTextField(
                    label: 'CODE',
                    hint: '123456',
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.pin_outlined,
                    validator: (v) => (v == null || v.trim().length != 6)
                        ? 'Enter the 6-digit code'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                AuthTextField(
                  label: 'NEW PASSWORD',
                  hint: '••••••••',
                  controller: _passCtrl,
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: (v) => (v == null || v.length < 6)
                      ? 'At least 6 characters'
                      : null,
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'CONFIRM PASSWORD',
                  hint: '••••••••',
                  controller: _confirmCtrl,
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: (v) =>
                      v != _passCtrl.text ? 'Passwords don\'t match' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center),
                  ),
                ],
                const SizedBox(height: 28),
                AppButton(
                  label: _isLoading ? 'Updating…' : 'Update Password',
                  onPressed: _isLoading ? null : _submit,
                  icon: Icons.check_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}