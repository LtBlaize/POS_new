// lib/shared/widgets/app_button.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

enum AppButtonVariant { primary, danger, success, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = false,
    this.loading = false,
  });

  Color get _bgColor => switch (variant) {
        AppButtonVariant.primary => AppColors.primary,
        AppButtonVariant.danger => AppColors.danger,
        AppButtonVariant.success => AppColors.success,
        AppButtonVariant.ghost => Colors.transparent,
      };

  Color get _fgColor => variant == AppButtonVariant.ghost
      ? AppColors.textPrimary
      : AppColors.textOnDark;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _fgColor),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: _fgColor),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(color: _fgColor)),
            ],
          );

    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _bgColor,
        foregroundColor: _fgColor,
        elevation: variant == AppButtonVariant.ghost ? 0 : 2,
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: variant == AppButtonVariant.ghost
              ? const BorderSide(color: AppColors.chipBorder)
              : BorderSide.none,
        ),
      ),
      child: child,
    );

    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}