// lib/features/admin/widgets/admin_colors.dart
//
// Deliberately separate from lib/shared/widgets/app_colors.dart. The plan
// calls for the admin shell to be "structurally separate from the POS
// Sidebar — not merged into one nav" and to "match the FluxPoint Admin
// mockup's visual language (clean SaaS style, not POS style)". AppColors is
// a dark POS theme (#1A1A2E/#16213E, accent #E94560); the mockup is a light
// SaaS dashboard (white/light-gray, blue accent). Reusing AppColors would
// fight the mockup at every turn, so this is its own palette instead.
import 'package:flutter/material.dart';

class AdminColors {
  AdminColors._();

  static const background = Color(0xFFF7F8FA);
  static const surface = Colors.white;
  static const sidebarBg = Colors.white;
  static const sidebarActiveBg = Color(0xFFEFF3FE);

  static const primary = Color(0xFF3B6FF3);   // logo, links, active nav, chart line
  static const primaryText = Color(0xFF3B6FF3);

  static const textPrimary = Color(0xFF13151A);
  static const textSecondary = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);

  static const border = Color(0xFFE5E7EB);
  static const divider = Color(0xFFEEF0F3);

  static const success = Color(0xFF16A34A);
  static const successBg = Color(0xFFE8F8EE);
  static const danger = Color(0xFFEF4444);
  static const dangerBg = Color(0xFFFDEBEB);
  static const warning = Color(0xFFF59E0B);
  static const warningBg = Color(0xFFFEF3DD);
  static const info = Color(0xFF3B82F6);
  static const infoBg = Color(0xFFEAF1FE);
  static const neutral = Color(0xFF9CA3AF);
  static const neutralBg = Color(0xFFF1F2F4);

  /// Status pill colors for subscription/payment status badges
  /// (Active/Trial/Expired/Suspended, Paid/Failed, etc).
  static (Color bg, Color fg) statusPillColors(String status) {
    return switch (status.toLowerCase()) {
      'active' || 'paid' || 'completed' => (successBg, success),
      'failed' || 'expired' => (dangerBg, danger),
      'trial' || 'pending' => (infoBg, info),
      'suspended' => (neutralBg, neutral),
      _ => (neutralBg, textSecondary),
    };
  }
}