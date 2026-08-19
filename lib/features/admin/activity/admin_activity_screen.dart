// lib/features/admin/activity/admin_activity_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_activity_providers.dart';

class AdminActivityScreen extends ConsumerWidget {
  const AdminActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _ActivityFilterBar(),
        const Divider(height: 1, color: AdminColors.divider),
        const Expanded(child: _ActivityListBody()),
        const _ActivityPaginationBar(),
      ],
    );
  }
}

class _ActivityFilterBar extends ConsumerWidget {
  const _ActivityFilterBar();

  void _update(WidgetRef ref, ActivityFilter Function(ActivityFilter) fn) {
    ref.read(activityFilterProvider.notifier).update(fn);
    ref.read(activityPageProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(activityFilterProvider);
    final actionsAsync = ref.watch(activityActionOptionsProvider);
    final targetsAsync = ref.watch(activityTargetTypeOptionsProvider);
    final adminsAsync = ref.watch(adminUserOptionsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          actionsAsync.maybeWhen(
            data: (actions) => _dropdown(
              value: filter.action,
              hint: 'All actions',
              items: actions,
              onChanged: (v) => _update(ref, (f) => f.copyWith(action: v)),
            ),
            orElse: () => const SizedBox(width: 140, height: 40),
          ),
          targetsAsync.maybeWhen(
            data: (types) => _dropdown(
              value: filter.targetType,
              hint: 'All target types',
              items: types,
              onChanged: (v) => _update(ref, (f) => f.copyWith(targetType: v)),
            ),
            orElse: () => const SizedBox(width: 140, height: 40),
          ),
          adminsAsync.maybeWhen(
            data: (admins) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AdminColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: filter.adminUserId,
                  hint: const Text('All admins', style: TextStyle(fontSize: 13, color: AdminColors.textMuted)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All admins')),
                    ...admins.map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.role} (${a.id.substring(0, 8)}…)'),
                        )),
                  ],
                  onChanged: (v) => _update(ref, (f) => f.copyWith(adminUserId: v)),
                  style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AdminColors.textMuted),
                ),
              ),
            ),
            orElse: () => const SizedBox(width: 180, height: 40),
          ),
          if (filter.action != null || filter.targetType != null || filter.adminUserId != null)
            TextButton(
              onPressed: () => _update(ref, (_) => const ActivityFilter()),
              child: const Text('Clear filters', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 13, color: AdminColors.textMuted)),
          items: [
            DropdownMenuItem(value: null, child: Text(hint)),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(i))),
          ],
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AdminColors.textMuted),
        ),
      ),
    );
  }
}

class _ActivityListBody extends ConsumerWidget {
  const _ActivityListBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activityListProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Could not load activity log', style: TextStyle(color: AdminColors.textMuted)),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Center(
            child: Text('No activity matches these filters', style: TextStyle(color: AdminColors.textMuted)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: page.items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AdminColors.divider),
          itemBuilder: (context, i) {
            final a = page.items[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: const BoxDecoration(color: AdminColors.primary, shape: BoxShape.circle),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${a.adminRole} (${a.adminIdShort}…)',
                        style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(a.action,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      a.targetType != null ? '${a.targetType}${a.targetId != null ? " #${a.targetId}" : ""}' : '—',
                      style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_fmtDateTime(a.createdAt),
                      style: const TextStyle(fontSize: 12, color: AdminColors.textMuted)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

String _fmtDateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _ActivityPaginationBar extends ConsumerWidget {
  const _ActivityPaginationBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(activityPageProvider);
    final async = ref.watch(activityListProvider);

    return async.maybeWhen(
      data: (result) {
        if (result.totalCount == 0) return const SizedBox(height: 56);
        final totalPages = result.totalPages;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AdminColors.divider))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${result.totalCount} entries', style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    color: page > 0 ? AdminColors.textPrimary : AdminColors.textMuted,
                    onPressed: page > 0 ? () => ref.read(activityPageProvider.notifier).state = page - 1 : null,
                  ),
                  Text('Page ${page + 1} of $totalPages', style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color: page + 1 < totalPages ? AdminColors.textPrimary : AdminColors.textMuted,
                    onPressed: page + 1 < totalPages ? () => ref.read(activityPageProvider.notifier).state = page + 1 : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox(height: 56),
    );
  }
}