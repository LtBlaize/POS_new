import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'table_provider.dart';
import '../settings/settings_provider.dart';
import '../../shared/widgets/app_colors.dart';

class TableSelector extends ConsumerStatefulWidget {
  const TableSelector({super.key});

  @override
  ConsumerState<TableSelector> createState() => _TableSelectorState();
}

class _TableSelectorState extends ConsumerState<TableSelector> {
  String? _activeRoomFilter; // local: which room tab is showing

  @override
  Widget build(BuildContext context) {
    final tableState = ref.watch(tableProvider);
    final rooms = ref.watch(settingsProvider).rooms;
    final allTables = tableState.tables;
    final selectedNumber = tableState.selectedTableNumber;
    final selectedRoomId = tableState.selectedRoomId;

    // Filter table chips by the active room tab
    final visibleTables = _activeRoomFilter == null
        ? allTables
        : allTables.where((t) => t.roomId == _activeRoomFilter).toList();

    // Decide label for active selection badge
    final selectedRoomName = selectedRoomId != null
        ? rooms.firstWhere(
            (r) => r.id == selectedRoomId,
            orElse: () => RoomEntry(id: '', name: 'Room', sortOrder: 0),
          ).name
        : null;

    final hasRooms = rooms.isNotEmpty;

    // If business uses rooms without tables, show room selector row
    final roomsOnly = hasRooms && allTables.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Room tabs (filter view when tables exist) ───────────────────
          if (hasRooms && !roomsOnly)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _SelectableChip(
                    label: 'All',
                    isSelected: _activeRoomFilter == null,
                    onTap: () =>
                        setState(() => _activeRoomFilter = null),
                  ),
                  ...rooms.map((room) => _SelectableChip(
                        label: room.name,
                        isSelected: _activeRoomFilter == room.id,
                        onTap: () =>
                            setState(() => _activeRoomFilter = room.id),
                      )),
                ],
              ),
            ),

          // ── Room selector (when no tables — KTV/private room mode) ──────
          if (roomsOnly)
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'Room',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      itemCount: rooms.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final room = rooms[index];
                        final isSelected = selectedRoomId == room.id;

                        return GestureDetector(
                          onTap: () => ref
                              .read(tableProvider.notifier)
                              .selectRoom(room.id),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 160),
                            constraints: const BoxConstraints(
                                minWidth: 72, maxWidth: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.divider,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.meeting_room_outlined,
                                  size: 14,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  room.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Active room badge
                  if (selectedRoomName != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(tableProvider.notifier)
                            .clearRoomSelection(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.meeting_room_outlined,
                                  size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                '$selectedRoomName  ✕',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Table chips (when tables exist) ─────────────────────────────
          if (!roomsOnly)
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'Table',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Expanded(
                    child: visibleTables.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                            child: Text(
                              'No tables in this room',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 10),
                            itemCount: visibleTables.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final table = visibleTables[index];
                              final isSelected =
                                  selectedNumber == table.number;
                              final isOccupied =
                                  table.status == TableStatus.occupied;
                              final isReserved =
                                  table.status == TableStatus.reserved;

                              Color bgColor;
                              Color borderColor;
                              Color textColor;

                              if (isSelected) {
                                bgColor = AppColors.primary;
                                borderColor = AppColors.primary;
                                textColor = Colors.white;
                              } else if (isOccupied) {
                                bgColor =
                                    AppColors.danger.withOpacity(0.08);
                                borderColor =
                                    AppColors.danger.withOpacity(0.4);
                                textColor = AppColors.danger;
                              } else if (isReserved) {
                                bgColor =
                                    AppColors.warning.withOpacity(0.08);
                                borderColor =
                                    AppColors.warning.withOpacity(0.4);
                                textColor = AppColors.warning;
                              } else {
                                bgColor = AppColors.surface;
                                borderColor = AppColors.divider;
                                textColor = AppColors.textSecondary;
                              }

                              return GestureDetector(
                                onTap: isOccupied
                                    ? null
                                    : () => ref
                                        .read(tableProvider.notifier)
                                        .selectTable(table.number),
                                child: AnimatedContainer(
                                  duration: const Duration(
                                      milliseconds: 160),
                                  width: 56,
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                        color: borderColor, width: 1.5),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${table.number}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: textColor,
                                        ),
                                      ),
                                      Text(
                                        isOccupied
                                            ? 'busy'
                                            : isReserved
                                                ? 'rsv'
                                                : isSelected
                                                    ? 'sel'
                                                    : 'free',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: textColor
                                              .withOpacity(0.8),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Active table badge
                  if (selectedNumber != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(tableProvider.notifier)
                            .clearSelection(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.table_restaurant_outlined,
                                  size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                'T$selectedNumber  ✕',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
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
}

// ── Shared selectable chip ────────────────────────────────────────────────────
class _SelectableChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(right: 6, top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}