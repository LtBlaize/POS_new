import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show deviceRoleProvider, DeviceRole;
import '../../../core/services/kitchen_alert_service.dart';
import '../../../core/services/kitchen_sound_settings.dart';
import '../../../shared/widgets/app_colors.dart';

class KitchenSoundSection extends ConsumerWidget {
  const KitchenSoundSection({super.key});

  void _snack(BuildContext ctx, String msg, {bool error = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _preview(
    BuildContext ctx,
    WidgetRef ref,
    KitchenSoundSettings s,
  ) async {
    final warn = await ref
        .read(kitchenAlertServiceProvider)
        .play(s, preview: true);
    if (warn != null && ctx.mounted) _snack(ctx, warn, error: true);
  }

  Future<void> _import(BuildContext ctx, WidgetRef ref) async {
    final r = await ref.read(kitchenAlertServiceProvider).importCustom();
    if (r.cancelled) return;
    if (r.error != null) {
      if (ctx.mounted) _snack(ctx, r.error!, error: true);
      return;
    }
    await ref
        .read(kitchenSoundSettingsProvider.notifier)
        .setCustom(r.path!, r.name!);
    if (ctx.mounted) _snack(ctx, 'Imported ${r.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(kitchenSoundSettingsProvider);
    final notifier = ref.read(kitchenSoundSettingsProvider.notifier);
    final isKitchenDevice = ref.watch(deviceRoleProvider) == DeviceRole.kitchen;
    final effective = s.enabledOverride ?? isKitchenDevice;
    final hasCustom = s.customPath != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kitchen sound alerts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Play sound when a new kitchen order arrives',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.enabledOverride == null
                        ? (isKitchenDevice
                            ? 'Auto: ON for this dedicated kitchen device'
                            : 'Auto: OFF on this device (turn on to enable)')
                        : 'Set manually for this device',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: effective,
                  onChanged: (v) => notifier.setEnabled(v),
                ),
                const Divider(height: 16),
                for (final b in kBuiltInSounds)
                  _SoundRow(
                    label: b.label,
                    selected: s.soundId == b.id,
                    onSelect: () => notifier.setSound(b.id),
                    onPreview:
                        () => _preview(
                          context,
                          ref,
                          s.copyWith(soundId: b.id, repeat: 1),
                        ),
                  ),
                _SoundRow(
                  label:
                      hasCustom
                          ? 'Custom: ${s.customName ?? 'imported sound'}'
                          : 'Custom sound (none imported)',
                  selected: s.soundId == kCustomSoundId,
                  onSelect:
                      hasCustom
                          ? () => notifier.setSound(kCustomSoundId)
                          : null,
                  onPreview:
                      hasCustom
                          ? () => _preview(
                            context,
                            ref,
                            s.copyWith(soundId: kCustomSoundId, repeat: 1),
                          )
                          : null,
                  trailing: TextButton(
                    onPressed: () => _import(context, ref),
                    child: Text(hasCustom ? 'Replace…' : 'Import…'),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'WAV, MP3 or OGG, up to 5 MB. OGG is not supported on Windows.',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    Expanded(
                      child: Slider(
                        value: s.volume,
                        divisions: 20,
                        label: '${(s.volume * 100).round()}%',
                        onChanged: (v) => notifier.setVolume(v),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${(s.volume * 100).round()}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Repeat', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    for (final n in [1, 2, 3])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${n}x'),
                          selected: s.repeat == n,
                          onSelected: (_) => notifier.setRepeat(n),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _preview(context, ref, s),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Test sound'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        await notifier.restoreDefaults();
                        if (context.mounted)
                          _snack(
                            context,
                            'Sound settings restored to defaults',
                          );
                      },
                      child: const Text('Restore defaults'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onPreview;
  final Widget? trailing;
  const _SoundRow({
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.onPreview,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      onSelect == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                ),
              ),
            ),
            if (trailing != null) trailing!,
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
              onPressed: onPreview,
            ),
          ],
        ),
      ),
    );
  }
}
