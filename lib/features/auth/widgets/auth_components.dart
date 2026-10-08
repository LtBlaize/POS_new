import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'auth_theme.dart';

/// Page shell: dark background, centered scrollable card, optional back button.
/// Scrolls instead of overflowing on small windows or when the keyboard opens.
class AuthScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final double maxWidth;
  final bool useCard;

  const AuthScaffold({
    super.key,
    required this.child,
    this.onBack,
    this.maxWidth = 480,
    this.useCard = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 480;
          final pad = narrow ? 16.0 : 24.0;
          final content = useCard
              ? Container(
                  padding: EdgeInsets.all(narrow ? 20 : 32),
                  decoration: BoxDecoration(
                    color: AuthColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AuthColors.border),
                  ),
                  child: child,
                )
              : child;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.all(pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, c.maxHeight - pad * 2),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onBack != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: onBack,
                            icon: const Icon(
                                Icons.arrow_back_ios_new_rounded, size: 14),
                            label: const Text('Back'),
                            style: TextButton.styleFrom(
                              foregroundColor: AuthColors.textSecondary,
                            ),
                          ),
                        ),
                      content,
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Shared 3-step indicator. [current] is 1-based.
class AuthStepper extends StatelessWidget {
  final int current;
  final int total;
  final String label;

  const AuthStepper({
    super.key,
    required this.current,
    this.total = 3,
    required this.label,
  });

  Widget _dot(int i) {
    final done = i < current;
    final active = i == current;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AuthColors.accent
            : active
                ? AuthColors.accent.withValues(alpha: 0.35)
                : AuthColors.field,
        border: active ? Border.all(color: AuthColors.accentLight, width: 2) : null,
        boxShadow: active
            ? [BoxShadow(
                color: AuthColors.accentLight.withValues(alpha: 0.45),
                blurRadius: 10)]
            : null,
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : Text(
              '$i',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AuthColors.textMuted,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = <Widget>[];
    for (var i = 1; i <= total; i++) {
      row.add(_dot(i));
      if (i < total) {
        row.add(Expanded(
          child: Container(
            height: 2,
            color: i < current ? AuthColors.accent : AuthColors.border,
          ),
        ));
      }
    }
    return Semantics(
      label: 'Step $current of $total, $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: row),
          const SizedBox(height: 12),
          Text('Step $current of $total — $label', style: AuthText.subtitle),
        ],
      ),
    );
  }
}

/// Full-width primary button. Disabled while [loading] (blocks double submit).
class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ButtonStyle(
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled) && !loading
                  ? AuthColors.accent.withValues(alpha: 0.35)
                  : AuthColors.accent),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled) && !loading
                  ? Colors.white54
                  : Colors.white),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else if (icon != null)
              Icon(icon, size: 18),
            if (loading || icon != null) const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AuthColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AuthColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 18, color: AuthColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    fontSize: 13, color: AuthColors.error, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated slot so showing/hiding an error doesn't jump the layout.
class AuthErrorSlot extends StatelessWidget {
  final String? message;
  const AuthErrorSlot(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AuthErrorBanner(message: message!),
            ),
    );
  }
}

class AuthInfoBanner extends StatelessWidget {
  final IconData icon;
  final Widget child;
  const AuthInfoBanner({super.key, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AuthColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuthColors.accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AuthColors.accentLight),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AuthSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const AuthSectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AuthColors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              style: const TextStyle(
                  fontSize: 13, color: AuthColors.textSecondary)),
        ],
      ],
    );
  }
}