// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'register_screen.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/auth_theme.dart';
import 'widgets/auth_components.dart';


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

      // Login succeeded. Navigation is handled by MyApp's auth listener.
      // If navigation takes a moment, keep the button disabled.
      if (!mounted) return;

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
    return AuthScaffold(
      maxWidth: 440,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AuthColors.accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.point_of_sale_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Welcome back',
                textAlign: TextAlign.center, style: AuthText.title),
            const SizedBox(height: 6),
            const Text('Sign in to your POS account',
                textAlign: TextAlign.center, style: AuthText.subtitle),
            const SizedBox(height: 28),

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
              controller: _passCtrl,
              isPassword: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isLoading) _submit();
              },
              prefixIcon: Icons.lock_outline_rounded,
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),

            AuthErrorSlot(_error),

            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                style: TextButton.styleFrom(
                    foregroundColor: AuthColors.accentLight),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 4),

            AuthButton(
              label: _isLoading ? 'Signing in…' : 'Sign In',
              loading: _isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),

            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text("Don't have an account?", style: AuthText.subtitle),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  style: TextButton.styleFrom(
                      foregroundColor: AuthColors.accentLight),
                  child: const Text('Register'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}