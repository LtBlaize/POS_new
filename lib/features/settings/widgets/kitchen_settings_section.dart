// lib/features/settings/widgets/kitchen_settings_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/app_colors.dart';
import '../../../config/business_config.dart';

class KitchenModeSelector extends ConsumerWidget {
  final BusinessConfig config;
  const KitchenModeSelector({super.key, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSingle = config.kitchenMode == 'single_device';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kitchen display mode',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.smartphone_rounded,
                  label: 'Same device',
                  description: 'Kitchen tab on this phone or tablet',
                  selected: isSingle,
                  onTap: () => _save(ref, 'single_device'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeCard(
                  icon: Icons.devices_rounded,
                  label: 'Dedicated device',
                  description: 'Separate tablet on the same WiFi',
                  selected: !isSingle,
                  onTap: () => _save(ref, 'dedicated_device'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Contextual hint
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: AppColors.primary.withOpacity(0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSingle
                        ? 'Orders appear directly in the Kitchen tab on this device. No WiFi setup needed.'
                        : 'Go to Settings → LAN Connection on the kitchen tablet and enter this device\'s IP address.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary.withOpacity(0.8),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _save(WidgetRef ref, String mode) {
    ref.read(settingsProvider.notifier).saveConfig(
          config.copyWith(kitchenMode: mode),
        );
  }
}

// ── Mode card ─────────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.07)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 10, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}