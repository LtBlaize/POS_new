import 'package:flutter/material.dart';
import 'auth_theme.dart';

class BusinessTypeCard extends StatelessWidget {
  final String type; // 'restaurant' | 'retail'
  final String label;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const BusinessTypeCard({
    super.key,
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? AuthColors.accent.withValues(alpha: 0.10)
                : AuthColors.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AuthColors.accentLight : AuthColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AuthColors.accent
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: isSelected ? Colors.white : AuthColors.textSecondary,
                    size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AuthColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(description,
                        style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AuthColors.textSecondary)),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: isSelected ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.check_circle_rounded,
                    color: AuthColors.accentLight, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}