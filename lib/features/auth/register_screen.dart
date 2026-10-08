// lib/features/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'otp_verification_screen.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/auth_theme.dart';
import 'widgets/auth_components.dart';

// Stores the pending user ID between step 1 and step 2
final pendingUserIdProvider = StateProvider<String?>((ref) => null);
final pendingSelectedPlanProvider = StateProvider<String?>((ref) => null);
// ── FIX: Store the owner PIN between step 1 and step 2 ───────────────────────
// Previously there was no PIN field on this screen, so pin_hash was stored
// as an empty default '0000' in completeRegistration. Now the owner sets
// their PIN on this screen and it's passed through to business_type_screen
// which calls completeRegistration with the real hashed value.
final pendingOwnerPinProvider = StateProvider<String?>((ref) => null);
final pendingFullNameProvider     = StateProvider<String?>((ref) => null);
final pendingBusinessNameProvider = StateProvider<String?>((ref) => null);
final pendingBusinessTypeProvider = StateProvider<String?>((ref) => null);
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _pinCtrl     = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(String raw) {
    if (raw.contains('already registered') || raw.contains('already in use')) {
      return 'This email is already registered.';
    }
    if (raw.contains('password')) return 'Password must be at least 6 characters.';
    if (raw.contains('email'))   return 'Enter a valid email address.';
    if (raw.contains('network')) return 'Network error. Check your connection.';
    return 'Something went wrong. Please try again.';
  }

  Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isLoading = true;
    _error = null;
  });

  // ✅ Set a sentinel BEFORE signUp fires the auth event.
  // The listener in main.dart checks this to know registration is in progress.
  ref.read(pendingUserIdProvider.notifier).state = 'pending';

  try {
    final userId = await ref.read(authServiceProvider).startRegistration(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );

    // Replace sentinel with the real userId
    ref.read(pendingUserIdProvider.notifier).state   = userId;
    ref.read(pendingOwnerPinProvider.notifier).state = _pinCtrl.text;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: _emailCtrl.text.trim(),
          ),
        ),
      );
    }
  } catch (e) {
    // Registration failed — clear the sentinel so the listener works normally
    ref.read(pendingUserIdProvider.notifier).state = null;
    debugPrint('Register error: $e');
    if (mounted) setState(() => _error = _friendlyError(e.toString()));
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      maxWidth: 480,
      onBack: () => Navigator.pop(context),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthStepper(current: 1, label: 'Account credentials'),
            const SizedBox(height: 24),
            const Text('Create your account', style: AuthText.title),
            const SizedBox(height: 24),

            AuthTextField(
              label: 'EMAIL',
              hint: 'you@example.com',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.mail_outline_rounded,
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),
            AuthTextField(
              label: 'PASSWORD',
              hint: '••••••••',
              helper: 'At least 6 characters',
              controller: _passCtrl,
              isPassword: true,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.lock_outline_rounded,
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 16),
            AuthTextField(
              label: 'CONFIRM PASSWORD',
              hint: '••••••••',
              controller: _confirmCtrl,
              isPassword: true,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.lock_outline_rounded,
              validator: (v) =>
                  v != _passCtrl.text ? 'Passwords do not match' : null,
            ),

            const SizedBox(height: 24),
            Container(height: 1, color: AuthColors.border),
            const SizedBox(height: 20),

            // Owner PIN — hashed in AuthService.hashPin(); logic unchanged.
            const AuthSectionHeader(
              title: 'Owner PIN',
              subtitle: 'Used to unlock the POS and access owner features.',
            ),
            const SizedBox(height: 16),
            AuthTextField(
              label: 'SET PIN (4–6 digits)',
              hint: '••••',
              controller: _pinCtrl,
              isPassword: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.pin_outlined,
              validator: (v) {
                if (v == null || v.length < 4) return 'Min 4 digits';
                if (v.length > 6) return 'Max 6 digits';
                return null;
              },
            ),
            const SizedBox(height: 16),
            AuthTextField(
              label: 'CONFIRM PIN',
              hint: '••••',
              controller: _pinConfirmCtrl,
              isPassword: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isLoading) _submit();
              },
              prefixIcon: Icons.pin_outlined,
              validator: (v) =>
                  v != _pinCtrl.text ? 'PINs do not match' : null,
            ),
            const SizedBox(height: 12),

            const AuthInfoBanner(
              icon: Icons.shield_outlined,
              child: Text(
                'Your PIN is encrypted before being saved. '
                'It cannot be recovered — keep it safe.',
                style: TextStyle(
                    fontSize: 12, color: AuthColors.textSecondary, height: 1.4),
              ),
            ),

            AuthErrorSlot(_error),
            const SizedBox(height: 24),

            AuthButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              loading: _isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}