// lib/shared/widgets/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF1A1A2E);
  static const sidebar = Color(0xFF16213E);
  static const surface = Color(0xFFF8F9FA);
  static const cardBg = Colors.white;

  static const primary = Color(0xFF0F3460);
  static const accent = Color(0xFFE94560);

  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF6C757D);
  static const textOnDark = Colors.white;

  static const success = Color(0xFF28A745);
  static const warning = Color(0xFFFFC107);
  static const danger = Color(0xFFDC3545);
  static const info = Color(0xFF17A2B8);

  static const divider = Color(0xFFDEE2E6);
  static const chipBorder = Color(0xFFCED4DA);

  static const border = Color.fromARGB(255, 15, 5, 5);

  // Status colors — matches order statuses
  static Color statusColor(String status) => switch (status) {
        'pending' => warning,
        'preparing' => info,
        'ready' => success,
        _ => textSecondary,
      };
}