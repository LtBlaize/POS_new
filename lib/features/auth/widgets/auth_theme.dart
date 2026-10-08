import 'package:flutter/material.dart';

/// Dark palette for the auth flow only (login → register → OTP → plan).
/// AppColors is light-theme and shared with the POS UI, so it is untouched.
class AuthColors {
  AuthColors._();
  static const background    = Color(0xFF12142A);
  static const card          = Color(0xFF1B1E33);
  static const field         = Color(0xFF24283F);
  static const border        = Color(0x1AFFFFFF); // white @ 10%
  static const accent        = Color(0xFF0B57E3);
  static const accentLight   = Color(0xFF4C8DFF);
  static const textPrimary   = Color(0xFFF1F3FA);
  static const textSecondary = Color(0xFF9CA3C0);
  static const textMuted     = Color(0xFF6B7194);
  static const error         = Color(0xFFF87171);
}

class AuthText {
  AuthText._();
  static const title = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w700,
    color: AuthColors.textPrimary, height: 1.2,
  );
  static const subtitle = TextStyle(
    fontSize: 14, color: AuthColors.textSecondary, height: 1.4,
  );
  static const label = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600,
    letterSpacing: 0.6, color: AuthColors.textSecondary,
  );
}