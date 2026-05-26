// lib/features/reports/widgets/audit_log_tab.dart
// Owner-only audit log viewer — filterable by action type, staff, date range.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_colors.dart';
import '../reports_providers.dart';


class AuditLogTab extends ConsumerStatefulWidget {
  const AuditLogTab({super.key});

  @override
  ConsumerState<AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends ConsumerState<AuditLogTab> {
  final _staffController = TextEditingController();

  static const _actionTypes = [
    ('All Actions',      null),
    ('Void item',        'void_item'),
    ('Void order',       'void_order'),
    ('Discount',         'discount_applied'),
    ('Override',         'manager_override'),
    ('Refund',           'order_refund'),
    ('Shift open',       'shift_open'),
    ('Shift close',      'shift_close'),
    ('Staff login',      'staff_login'),
    ('Settings',         'settings_changed'),
    ('Inventory adjust', 'inventory_adjust'),
    ('Credit',           'credit_added'),
  ];

  @override
  void dispose() {
    _staffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(auditFilterProvider);
    final logsAsync = ref.watch(auditLogProvider(filter));

    return Column(
      children: [
        // ── Filter bar ───────────────────────────────────────────────────────
        _FilterBar(
          filter: filter,
          staffController: _staffController,
          actionTypes: _actionTypes,
          onFilterChanged: (f) =>
              ref.read(auditFilterProvider.notifier).state = f,
          onClear: () {
            _staffController.clear();
            ref.read(auditFilterProvider.notifier).state =
                const AuditFilter();
          },
        ),

        // ── Log list ─────────────────────────────────────────────────────────
        Expanded(
          child: logsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Error loading audit log: $e',
                  style: const TextStyle(color: AppColors.danger)),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 48,
                          color:
                              AppColors.textSecondary.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      const Text('No audit entries found',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      const Text(
                        'Actions like voids, discounts and logins\nwill appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: entries.length,
                itemBuilder: (_, i) => _AuditEntryCard(entry: entries[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BAR
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final AuditFilter filter;
  final TextEditingController staffController;
  final List<(String, String?)> actionTypes;
  final ValueChanged<AuditFilter> onFilterChanged;
  final VoidCallback onClear;

  const _FilterBar({
    required this.filter,
    required this.staffController,
    required this.actionTypes,
    required this.onFilterChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = filter.actionType != null ||
        (filter.staffName?.isNotEmpty ?? false) ||
        filter.from != null ||
        filter.to != null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Action type chips ──────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: actionTypes.map((pair) {
                final (label, value) = pair;
                final active = filter.actionType == value;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => onFilterChanged(
                        filter.copyWith(actionType: value)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary.withOpacity(0.1)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.primary.withOpacity(0.4)
                              : AppColors.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (value != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                _iconForAction(value),
                                size: 11,
                                color: active
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // ── Staff search + date range + clear ──────────────────────────
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: staffController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search by staff name…',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search,
                          size: 16, color: AppColors.textSecondary),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    onChanged: (v) => onFilterChanged(
                        filter.copyWith(staffName: v.isEmpty ? null : v)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _DateRangeButton(
                from: filter.from,
                to: filter.to,
                onPick: (from, to) =>
                    onFilterChanged(filter.copyWith(from: from, to: to)),
              ),
              if (hasActiveFilter) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: const Text('Clear',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForAction(String action) => switch (action) {
        'void_item'         => Icons.remove_circle_outline,
        'void_order'        => Icons.remove_shopping_cart_outlined,
        'discount_applied'  => Icons.local_offer_outlined,
        'manager_override'  => Icons.admin_panel_settings_outlined,
        'order_refund'      => Icons.replay_outlined,
        'shift_open'        => Icons.login_rounded,
        'shift_close'       => Icons.logout_rounded,
        'staff_login'       => Icons.person_outline,
        'settings_changed'  => Icons.settings_outlined,
        'inventory_adjust'  => Icons.inventory_2_outlined,
        'credit_added'      => Icons.receipt_long_outlined,
        'credit_paid'       => Icons.payments_outlined,
        _                   => Icons.history_rounded,
      };
}

class _DateRangeButton extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onPick;

  const _DateRangeButton({
    required this.from,
    required this.to,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final hasRange = from != null || to != null;

    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final result = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now,
          initialDateRange: from != null && to != null
              ? DateTimeRange(start: from!, end: to!)
              : null,
        );
        if (result != null) {
          onPick(result.start, result.end);
        }
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hasRange
              ? AppColors.info.withOpacity(0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasRange
                ? AppColors.info.withOpacity(0.4)
                : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_outlined,
                size: 14,
                color: hasRange
                    ? AppColors.info
                    : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              hasRange
                  ? '${_fmt(from!)} – ${_fmt(to!)}'
                  : 'Date range',
              style: TextStyle(
                fontSize: 12,
                color: hasRange
                    ? AppColors.info
                    : AppColors.textSecondary,
                fontWeight: hasRange
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}';
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIT ENTRY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AuditEntryCard extends StatefulWidget {
  final AuditLogEntry entry;
  const _AuditEntryCard({required this.entry});

  @override
  State<_AuditEntryCard> createState() => _AuditEntryCardState();
}

class _AuditEntryCardState extends State<_AuditEntryCard> {
  bool _expanded = false;

  static const _actionColors = <String, Color>{
    'void_item':         Color(0xFFE94560),
    'void_order':        Color(0xFFE94560),
    'discount_applied':  Color(0xFFF59E0B),
    'manager_override':  Color(0xFFFF9800),
    'price_override':    Color(0xFFFF9800),
    'shift_open':        Color(0xFF10B981),
    'shift_close':       Color(0xFF6366F1),
    'staff_login':       Color(0xFF3B82F6),
    'staff_logout':      Color(0xFF8B5CF6),
    'settings_changed':  Color(0xFF6B7280),
    'order_refund':      Color(0xFFE94560),
    'inventory_adjust':  Color(0xFF3B82F6),
    'credit_added':      Color(0xFF8B5CF6),
    'credit_paid':       Color(0xFF10B981),
  };

  static const _actionLabels = <String, String>{
    'void_item':         'Void item',
    'void_order':        'Void order',
    'discount_applied':  'Discount',
    'manager_override':  'Override',
    'price_override':    'Price override',
    'shift_open':        'Shift open',
    'shift_close':       'Shift close',
    'staff_login':       'Login',
    'staff_logout':      'Logout',
    'settings_changed':  'Settings',
    'order_refund':      'Refund',
    'inventory_adjust':  'Inventory',
    'credit_added':      'Credit added',
    'credit_paid':       'Credit paid',
  };

  IconData _iconFor(String action) => switch (action) {
        'void_item'         => Icons.remove_circle_outline,
        'void_order'        => Icons.remove_shopping_cart_outlined,
        'discount_applied'  => Icons.local_offer_outlined,
        'manager_override'  => Icons.admin_panel_settings_outlined,
        'price_override'    => Icons.edit_outlined,
        'shift_open'        => Icons.login_rounded,
        'shift_close'       => Icons.logout_rounded,
        'staff_login'       => Icons.person_outline,
        'staff_logout'      => Icons.person_off_outlined,
        'settings_changed'  => Icons.settings_outlined,
        'order_refund'      => Icons.replay_outlined,
        'inventory_adjust'  => Icons.inventory_2_outlined,
        'credit_added'      => Icons.receipt_long_outlined,
        'credit_paid'       => Icons.payments_outlined,
        _                   => Icons.history_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color =
        _actionColors[entry.actionType] ?? AppColors.textSecondary;
    final label =
        _actionLabels[entry.actionType] ?? entry.actionType;
    final hasMetadata =
        entry.metadata != null && entry.metadata!.isNotEmpty;
    final hasAuthoriser = entry.authorisedByName != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // ── Main row ───────────────────────────────────────────────────
          GestureDetector(
            onTap: hasMetadata
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_iconFor(entry.actionType),
                        size: 16, color: color),
                  ),
                  const SizedBox(width: 10),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _timeAgo(entry.createdAt),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(entry.description,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              entry.performedByName,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                            Text(
                              ' · ${_roleLabel(entry.performedByRole)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                            if (hasAuthoriser) ...[
                              const Text(' · ',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                              const Icon(
                                  Icons.admin_panel_settings_outlined,
                                  size: 11,
                                  color: Color(0xFFFF9800)),
                              const SizedBox(width: 2),
                              Text(
                                entry.authorisedByName!,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFFF9800),
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Expand chevron
                  if (hasMetadata)
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),

          // ── Metadata detail ────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _expanded && hasMetadata
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: entry.metadata!.entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${e.value}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _roleLabel(String role) => switch (role) {
        'owner'   => 'Owner',
        'manager' => 'Manager',
        'cashier' => 'Cashier',
        'kitchen' => 'Kitchen',
        _         => role,
      };
}