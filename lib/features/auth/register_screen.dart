// lib/features/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'business_type_screen.dart';
import 'widgets/auth_text_field.dart';
import '../../shared/widgets/app_colors.dart';
import '../../shared/widgets/app_button.dart';

// Stores the pending user ID between step 1 and step 2
final pendingUserIdProvider = StateProvider<String?>((ref) => null);

// ── FIX: Store the owner PIN between step 1 and step 2 ───────────────────────
// Previously there was no PIN field on this screen, so pin_hash was stored
// as an empty default '0000' in completeRegistration. Now the owner sets
// their PIN on this screen and it's passed through to business_type_screen
// which calls completeRegistration with the real hashed value.
final pendingOwnerPinProvider = StateProvider<String?>((ref) => null);

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
        MaterialPageRoute(builder: (_) => const BusinessTypeScreen()),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
          ),
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
                const SizedBox(height: 8),

                // Step indicator
                Row(
                  children: [
                    _StepDot(active: true,  label: '1', done: false),
                    _StepLine(active: false),
                    _StepDot(active: false, label: '2', done: false),
                  ],
                ),
                const SizedBox(height: 28),

                const Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Step 1 of 2 — Account credentials',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 36),

                // ── Email & password ─────────────────────────────────────────
                AuthTextField(
                  label: 'EMAIL',
                  hint: 'you@example.com',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.mail_outline_rounded,
                  validator: (v) =>
                      (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                ),
                const SizedBox(height: 20),

                AuthTextField(
                  label: 'PASSWORD',
                  hint: '••••••••',
                  controller: _passCtrl,
                  isPassword: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
                const SizedBox(height: 20),

                AuthTextField(
                  label: 'CONFIRM PASSWORD',
                  hint: '••••••••',
                  controller: _confirmCtrl,
                  isPassword: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: (v) =>
                      v != _passCtrl.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 32),

                // ── FIX: Owner PIN ───────────────────────────────────────────
                // This PIN is used for the staff PIN lock overlay (pin_lock_overlay.dart).
                // It is SHA-256 hashed in AuthService.hashPin() before being
                // stored in the staff_members table — never stored as plain text.
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Owner PIN',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Used to unlock the POS and access owner features.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),

                _PinField(
                  label: 'SET PIN (4–6 digits)',
                  controller: _pinCtrl,
                  validator: (v) {
                    if (v == null || v.length < 4) return 'Min 4 digits';
                    if (v.length > 6)              return 'Max 6 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _PinField(
                  label: 'CONFIRM PIN',
                  controller: _pinConfirmCtrl,
                  validator: (v) =>
                      v != _pinCtrl.text ? 'PINs do not match' : null,
                ),
                const SizedBox(height: 8),

                // Security note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your PIN is encrypted before being saved. '
                          'It cannot be recovered — keep it safe.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha:0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                AppButton(
                  label: 'Continue',
                  onPressed: _isLoading ? null : _submit,
                  icon: Icons.arrow_forward_rounded,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── PIN input widget ──────────────────────────────────────────────────────────
// Numeric-only, obscured, styled to match AuthTextField.

class _PinField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  const _PinField({
    required this.label,
    required this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',           // hide the "0/6" counter
        prefixIcon: const Icon(
          Icons.pin_outlined,
          color: AppColors.textSecondary,
        ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

// ── Step indicator widgets ────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;

  const _StepDot({
    required this.active,
    required this.done,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.primary : AppColors.border,
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        color: active ? AppColors.primary : AppColors.border,
      ),
    );
  }
}