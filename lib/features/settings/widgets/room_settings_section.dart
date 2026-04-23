import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings_provider.dart';
import '../../../shared/widgets/app_colors.dart';

class RoomSettingsSection extends ConsumerStatefulWidget {
  const RoomSettingsSection({super.key});

  @override
  ConsumerState<RoomSettingsSection> createState() =>
      _RoomSettingsSectionState();
}

class _RoomSettingsSectionState extends ConsumerState<RoomSettingsSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(settingsProvider).rooms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.meeting_room_outlined,
          title: 'Rooms / Areas',
          subtitle: '${rooms.length} total',
        ),
        const SizedBox(height: 12),

        // ── Add room input ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add room',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'e.g. Main Hall, VIP Room, Terrace',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _addRoom(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Add',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Room chips ──────────────────────────────────────────────────────
        if (rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No rooms yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rooms.map((r) => _RoomChip(room: r)).toList(),
          ),
      ],
    );
  }

  void _addRoom() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    final rooms = ref.read(settingsProvider).rooms;
    final duplicate = rooms.any(
      (r) => r.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" already exists')),
      );
      return;
    }

    ref.read(settingsProvider.notifier).addRoom(name);
    _controller.clear();
  }
}

// ── Room chip with delete ─────────────────────────────────────────────────────
class _RoomChip extends ConsumerWidget {
  final RoomEntry room;
  const _RoomChip({required this.room});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.meeting_room_outlined,
              size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            room.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete room?'),
                  content: Text(
                      '"${room.name}" will be removed. Tables in this room will become ungrouped.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete',
                            style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              );
              if (confirm == true) {
                ref.read(settingsProvider.notifier).deleteRoom(room.id);
              }
            },
            child: const Icon(Icons.close,
                size: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text('· $subtitle',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}