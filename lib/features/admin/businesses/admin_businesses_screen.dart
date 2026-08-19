// lib/features/admin/businesses/admin_businesses_screen.dart
//
// Phase 6. List view for /admin/businesses — search, plan/status/trial
// filters, and real server-side pagination via businessPageProvider.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_businesses_providers.dart';

class AdminBusinessesScreen extends ConsumerWidget {
  const AdminBusinessesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _FilterBar(),
        const Divider(height: 1, color: AdminColors.divider),
        Expanded(child: const _BusinessListBody()),
        const _PaginationBar(),
      ],
    );
  }
}

// ── Filters ──────────────────────────────────────────────────────────────

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();
  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: ref.read(businessFilterProvider).search);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateFilter(BusinessFilter Function(BusinessFilter) update) {
    ref.read(businessFilterProvider.notifier).update(update);
    ref.read(businessPageProvider.notifier).state = 0; // reset to page 1 on any filter change
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(businessFilterProvider);
    final plansAsync = ref.watch(businessPlanOptionsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => _updateFilter((f) => f.copyWith(search: v)),
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search, size: 18, color: AdminColors.textMuted),
                isDense: true,
                filled: true,
                fillColor: AdminColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AdminColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          plansAsync.when(
            loading: () => const SizedBox(width: 140, height: 40),
            error: (_, __) => const SizedBox.shrink(),
            data: (plans) => _Dropdown<String?>(
              value: filter.plan,
              hint: 'All plans',
              items: [
                const DropdownMenuItem(value: null, child: Text('All plans')),
                ...plans.map((p) => DropdownMenuItem(value: p, child: Text(p))),
              ],
              onChanged: (v) => _updateFilter((f) => f.copyWith(plan: v)),
            ),
          ),
          _Dropdown<ActiveFilter>(
            value: filter.activeFilter,
            hint: 'Status',
            items: const [
              DropdownMenuItem(value: ActiveFilter.all, child: Text('All statuses')),
              DropdownMenuItem(value: ActiveFilter.active, child: Text('Active')),
              DropdownMenuItem(value: ActiveFilter.inactive, child: Text('Inactive')),
            ],
            onChanged: (v) => _updateFilter((f) => f.copyWith(activeFilter: v ?? ActiveFilter.all)),
          ),
          FilterChip(
            label: const Text('Trial expiring ≤7d'),
            selected: filter.trialExpiringSoon,
            onSelected: (v) => _updateFilter((f) => f.copyWith(trialExpiringSoon: v)),
            selectedColor: AdminColors.infoBg,
            checkmarkColor: AdminColors.info,
            labelStyle: TextStyle(
              color: filter.trialExpiringSoon ? AdminColors.info : AdminColors.textSecondary,
              fontSize: 12,
            ),
            side: const BorderSide(color: AdminColors.border),
            backgroundColor: AdminColors.surface,
          ),
          if (filter.search.isNotEmpty ||
              filter.plan != null ||
              filter.activeFilter != ActiveFilter.all ||
              filter.trialExpiringSoon)
            TextButton(
              onPressed: () {
                _searchCtrl.clear();
                _updateFilter((_) => const BusinessFilter());
              },
              child: const Text('Clear filters', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _Dropdown({required this.value, required this.hint, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            hint: Text(hint, style: const TextStyle(fontSize: 13, color: AdminColors.textMuted)),
            items: items,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AdminColors.textMuted),
          ),
        ),
      );
}

// ── List body ────────────────────────────────────────────────────────────

class _BusinessListBody extends ConsumerWidget {
  const _BusinessListBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(businessListProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Could not load businesses', style: TextStyle(color: AdminColors.textMuted)),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Center(
            child: Text('No businesses match these filters', style: TextStyle(color: AdminColors.textMuted)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: page.items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AdminColors.divider),
          itemBuilder: (context, i) {
            final b = page.items[i];
            final (pillBg, pillFg) = AdminColors.statusPillColors(b.isActive ? 'active' : 'suspended');
            final trialSoon = b.trialEndsAt != null &&
                b.trialEndsAt!.isAfter(DateTime.now()) &&
                b.trialEndsAt!.difference(DateTime.now()).inDays <= 7;

            return InkWell(
              onTap: () => Navigator.pushNamed(context, '/admin/businesses/${b.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(b.businessType,
                              style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(b.subscriptionPlan,
                          style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary)),
                    ),
                    Expanded(
                      flex: 2,
                      child: trialSoon
                          ? Row(
                              children: [
                                const Icon(Icons.access_time, size: 13, color: AdminColors.warning),
                                const SizedBox(width: 4),
                                Text('Trial ends ${_shortDate(b.trialEndsAt!)}',
                                    style: const TextStyle(fontSize: 12, color: AdminColors.warning)),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(20)),
                      child: Text(b.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: pillFg)),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.chevron_right, size: 18, color: AdminColors.textMuted),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _shortDate(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

// ── Pagination ───────────────────────────────────────────────────────────

class _PaginationBar extends ConsumerWidget {
  const _PaginationBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(businessPageProvider);
    final async = ref.watch(businessListProvider);

    return async.maybeWhen(
      data: (result) {
        if (result.totalCount == 0) return const SizedBox(height: 56);
        final totalPages = result.totalPages;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AdminColors.divider)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${result.totalCount} businesses',
                  style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    color: page > 0 ? AdminColors.textPrimary : AdminColors.textMuted,
                    onPressed: page > 0 ? () => ref.read(businessPageProvider.notifier).state = page - 1 : null,
                  ),
                  Text('Page ${page + 1} of $totalPages',
                      style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color: page + 1 < totalPages ? AdminColors.textPrimary : AdminColors.textMuted,
                    onPressed:
                        page + 1 < totalPages ? () => ref.read(businessPageProvider.notifier).state = page + 1 : null,
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