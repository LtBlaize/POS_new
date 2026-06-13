// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'register_screen.dart';
import 'widgets/auth_text_field.dart';
import '../../shared/widgets/app_colors.dart';
import '../../shared/widgets/app_button.dart';

// ── FIX: Removed import of main.dart ─────────────────────────────────────────
// login_screen.dart previously imported main.dart to access DeviceRole and
// deviceRoleProvider so it could navigate manually. That import is now gone
// because navigation is handled entirely by MyApp's authStateProvider
// listener. This screen only calls authServiceProvider.login().

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(String raw) {
    if (raw.contains('credentials') || raw.contains('Invalid login')) {
      return 'Incorrect email or password.';
    }
    if (raw.contains('email')) return 'Invalid email address.';
    if (raw.contains('network')) return 'Network error. Check your connection.';
    return 'Something went wrong. Please try again.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ── FIX: Only authenticate — do NOT navigate ───────────────────────────
      //
      // Previously this method did 4 things:
      //   1. login()
      //   2. await profileProvider.future          ← caused the race
      //   3. SharedPreferences.setString           ← now in MyApp listener
      //   4. Navigator.pushReplacementNamed(...)   ← caused the redirect loop
      //
      // Now it does exactly ONE thing: call login().
      //
      // After login() returns, Supabase fires an authStateChange event.
      // MyApp's ref.listen(authStateProvider) catches it, loads the profile,
      // saves business_id to SharedPreferences, and navigates to the correct
      // route. No race, no double-navigation, no redirect loop.
      await ref.read(authServiceProvider).login(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );

      // ✅ Done. Do not call Navigator here.
      // The auth listener in MyApp (main.dart) takes over from here.
      // _isLoading will naturally reset when the widget is replaced.

    } catch (e) {
      // login() throws if credentials are wrong or network fails.
      // Show the error and reset the loading state so user can retry.
      if (mounted) {
        setState(() {
          _error = _friendlyError(e.toString());
          _isLoading = false;
        });
      }
    }
    // Note: we do NOT call setState(_isLoading = false) on success.
    // The screen will be replaced by /pos or /role-select, so there's
    // no point resetting state — it would cause a brief flash.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),

                  // Logo
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to your POS account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 40),

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
                        (v == null || v.length < 6)
                            ? 'Min 6 characters'
                            : null,
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

                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/forgot-password'),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  AppButton(
                    label: _isLoading ? 'Signing in…' : 'Sign In',
                    onPressed: _isLoading ? null : _submit,
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        ),
                        child: const Text(
                          'Register',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}