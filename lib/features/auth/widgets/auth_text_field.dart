import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_theme.dart';

class AuthTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  // optional additions
  final String? helper;
  final bool enabled;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.prefixIcon,
    this.helper,
    this.enabled = true,
    this.maxLength,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AuthText.label),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.isPassword && _obscure,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          maxLength: widget.maxLength,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          cursorColor: AuthColors.accentLight,
          keyboardAppearance: Brightness.dark,
          style: const TextStyle(fontSize: 15, color: AuthColors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: AuthColors.textMuted),
            helperText: widget.helper,
            helperStyle:
                const TextStyle(fontSize: 12, color: AuthColors.textMuted),
            errorStyle: const TextStyle(fontSize: 12, color: AuthColors.error),
            errorMaxLines: 2,
            counterText: '',
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon,
                    size: 20, color: AuthColors.textMuted)
                : null,
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AuthColors.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
            filled: true,
            fillColor: AuthColors.field,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: _border(AuthColors.border),
            enabledBorder: _border(AuthColors.border),
            disabledBorder: _border(AuthColors.border),
            focusedBorder: _border(AuthColors.accentLight, 1.5),
            errorBorder: _border(AuthColors.error),
            focusedErrorBorder: _border(AuthColors.error, 1.5),
          ),
        ),
      ],
    );
  }
}