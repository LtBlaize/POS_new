// features/reports/reports_screen.dart
// Screen shell + header + tab switcher only.
// All data lives in reports_providers.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/feature_manager.dart';
import '../../core/services/connectivity_service.dart';
import '../../shared/widgets/app_colors.dart';
import 'reports_providers.dart';
import 'widgets/daily_tab.dart';
import 'widgets/export_button.dart';   // FIX: was never imported
import 'widgets/shifts_tab.dart';
import 'widgets/audit_log_tab.dart';
import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT HELPER
// ─────────────────────────────────────────────────────────────────────────────

enum ReportLayout { phone, tablet, desktop }

ReportLayout layoutOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return ReportLayout.phone;
  if (w < 1024) return ReportLayout.tablet;
  return ReportLayout.desktop;
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerWidget {
  final FeatureManager featureManager;
  const ReportsScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final dateRange = ref.watch(dateRangeProvider);
    final activeTab = ref.watch(reportTabProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final isRestaurant = featureManager.hasFeature('kitchen') ||
        featureManager.hasFeature('tables');
    final layout = layoutOf(context);

    final isRangeMode = !dateRange.isSingleDay;

    // Use period provider when range selected, daily otherwise
    final reportAsync = isRangeMode
        ? ref.watch(periodReportProvider(dateRange))
        : ref.watch(dailyReportProvider(selectedDate));
    final shiftAsync = ref.watch(shiftReportProvider(selectedDate));

    final dailyReport = reportAsync.valueOrNull;
    final shifts = shiftAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Offline banner ────────────────────────────────────────────────
          if (!isOnline)
            Container(
              width: double.infinity,
              color: const Color(0xFFB71C1C),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Offline — showing cached report data',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          // ── Header ───────────────────────────────────────────────────────
          ReportHeader(
            selectedDate: selectedDate,
            dateRange: dateRange,
            isRestaurant: isRestaurant,
            layout: layout,
            activeTab: activeTab,
            dailyReport: dailyReport,
            shifts: shifts,
            onTabChanged: (t) =>
                ref.read(reportTabProvider.notifier).state = t,
            onPrev: isRangeMode
                ? null
                : () => ref.read(selectedDateProvider.notifier).state =
                    selectedDate.subtract(const Duration(days: 1)),
            onNext: isRangeMode || _isToday(selectedDate)
                ? null
                : () => ref.read(selectedDateProvider.notifier).state =
                    selectedDate.add(const Duration(days: 1)),
            onPick: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                ref.read(selectedDateProvider.notifier).state = picked;
                ref.read(dateRangeProvider.notifier).state = DateRange(
                  start: picked,
                  end: picked,
                  preset: RangePreset.day,
                );
              }
            },
            onToday: _isToday(selectedDate) && !isRangeMode
                ? null
                : () {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    ref.read(selectedDateProvider.notifier).state = today;
                    ref.read(dateRangeProvider.notifier).state = DateRange(
                      start: today,
                      end: today,
                      preset: RangePreset.day,
                    );
                  },
            onRangeChanged: (range) {
              ref.read(dateRangeProvider.notifier).state = range;
              ref.read(selectedDateProvider.notifier).state = range.start;
            },
            onRangePick: () async {
              final now = DateTime.now();
              final result = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: now,
                initialDateRange: DateTimeRange(
                  start: dateRange.start,
                  end: dateRange.end,
                ),
              );
              if (result != null) {
                ref.read(dateRangeProvider.notifier).state = DateRange(
                  start: result.start,
                  end: result.end,
                  preset: RangePreset.custom,
                );
                ref.read(selectedDateProvider.notifier).state = result.start;
              }
            },
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: activeTab == ReportTab.auditLog
                ? const AuditLogTab()
                : activeTab == ReportTab.daily
                    ? reportAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Error loading report: $e',
                                style: const TextStyle(
                                    color: AppColors.danger)),
                          ),
                        ),
                        data: (report) => DailyTab(
                          report: report,
                          isRestaurant: isRestaurant,
                          layout: layout,
                          isToday: _isToday(selectedDate) && !isRangeMode,
                          dateRange: isRangeMode ? dateRange : null,
                        ),
                      )
                    : shiftAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Error loading shifts: $e',
                                style: const TextStyle(
                                    color: AppColors.danger)),
                          ),
                        ),
                        data: (entries) => ShiftsTab(
                          entries: entries,
                          layout: layout,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class ReportHeader extends StatelessWidget {
  final DateTime selectedDate;
  final DateRange dateRange;
  final bool isRestaurant;
  final ReportLayout layout;
  final ReportTab activeTab;
  final ValueChanged<ReportTab> onTabChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final VoidCallback? onToday;
  final ValueChanged<DateRange> onRangeChanged;
  final VoidCallback onRangePick;
  final DailyReport? dailyReport;
  final List<ShiftEntry>? shifts;

  const ReportHeader({
    super.key,
    required this.selectedDate,
    required this.dateRange,
    required this.isRestaurant,
    required this.layout,
    required this.activeTab,
    required this.onTabChanged,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToday,
    required this.onRangeChanged,
    required this.onRangePick,
    required this.dailyReport,
    required this.shifts,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = layout == ReportLayout.phone;
    final pad = isPhone ? 16.0 : 24.0;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(pad, isPhone ? 14 : 20, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isPhone
              ? _phoneTitleRow(selectedDate, isRestaurant, dailyReport, shifts, dateRange)
          : _wideTitleRow(selectedDate, isRestaurant, dailyReport, shifts, dateRange),
          SizedBox(height: isPhone ? 10 : 14),
          isPhone ? _phoneDateRow() : _wideDateRow(),
          const SizedBox(height: 8),
          _RangePresetRow(
            current: dateRange,
            onChanged: onRangeChanged,
            onCustomPick: onRangePick,
          ),
          SizedBox(height: isPhone ? 8 : 10),
          TabSwitcher(active: activeTab, onChanged: onTabChanged),
        ],
      ),
    );
  }

  // FIX: title rows now include the ExportButton on the trailing edge
  Widget _phoneTitleRow(
    DateTime date,
    bool isRestaurant,
    DailyReport? dailyReport,
    List<ShiftEntry>? shifts,
    DateRange dateRange,
  ) =>
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TypeBadge(isRestaurant: isRestaurant),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(date),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // FIX: ExportButton placed here — was missing entirely before
          ExportButton(
            date: date,
            dateRange: dateRange,
            dailyReport: dailyReport,
            shifts: shifts,
          ),
        ],
      );

  Widget _wideTitleRow(
    DateTime date,
    bool isRestaurant,
    DailyReport? dailyReport,
    List<ShiftEntry>? shifts,
    DateRange dateRange,
  ) =>
      Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Reports',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TypeBadge(isRestaurant: isRestaurant),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(date),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          // FIX: ExportButton placed here — was missing entirely before
          ExportButton(
            date: date,
            dateRange: dateRange,
            dailyReport: dailyReport,
            shifts: shifts,
          ),
        ],
      );

  Widget _phoneDateRow() => Row(
        children: [
          DateNavButton(icon: Icons.chevron_left, onTap: onPrev),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: onPick,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      _formatDateShort(selectedDate),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          DateNavButton(icon: Icons.chevron_right, onTap: onNext),
          if (onToday != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onToday,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Today',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      );

  Widget _wideDateRow() => Row(
        children: [
          DateNavButton(icon: Icons.chevron_left, onTap: onPrev),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onPick,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    _formatDateShort(selectedDate),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          DateNavButton(icon: Icons.chevron_right, onTap: onNext),
          if (onToday != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onToday,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Today',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
          const Spacer(),
        ],
      );

  static String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _formatDateShort(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB SWITCHER
// ─────────────────────────────────────────────────────────────────────────────

class TabSwitcher extends ConsumerWidget {
  final ReportTab active;
  final ValueChanged<ReportTab> onChanged;

  const TabSwitcher({super.key, required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeStaff = ref.watch(activeStaffProvider);
    final isOwner = activeStaff?.role == StaffRole.owner;

    return Row(
      children: [
        _Tab(
          label: 'Daily Sales',
          icon: Icons.bar_chart_rounded,
          active: active == ReportTab.daily,
          onTap: () => onChanged(ReportTab.daily),
        ),
        const SizedBox(width: 4),
        _Tab(
          label: 'Shift Reports',
          icon: Icons.people_alt_outlined,
          active: active == ReportTab.shifts,
          onTap: () => onChanged(ReportTab.shifts),
        ),
        if (isOwner) ...[
          const SizedBox(width: 4),
          _Tab(
            label: 'Audit Log',
            icon: Icons.history_rounded,
            active: active == ReportTab.auditLog,
            onTap: () => onChanged(ReportTab.auditLog),
          ),
        ],
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    active ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL HEADER WIDGETS (used only in header)
// ─────────────────────────────────────────────────────────────────────────────

class TypeBadge extends StatelessWidget {
  final bool isRestaurant;
  const TypeBadge({super.key, required this.isRestaurant});

  @override
  Widget build(BuildContext context) {
    final color =
        isRestaurant ? const Color(0xFF1A1A2E) : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isRestaurant ? 'Restaurant' : 'Retail',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class DateNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const DateNavButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
          color: onTap == null ? AppColors.surface : Colors.white,
        ),
        child: Icon(icon,
            size: 16,
            color: onTap == null
                ? AppColors.textSecondary.withOpacity(0.3)
                : AppColors.textSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RANGE PRESET ROW
// ─────────────────────────────────────────────────────────────────────────────

class _RangePresetRow extends StatelessWidget {
  final DateRange current;
  final ValueChanged<DateRange> onChanged;
  final VoidCallback onCustomPick;

  const _RangePresetRow({
    required this.current,
    required this.onChanged,
    required this.onCustomPick,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PresetChip(
            label: 'Today',
            active: current.preset == RangePreset.day,
            onTap: () => onChanged(DateRange(
              start: today,
              end: today,
              preset: RangePreset.day,
            )),
          ),
          const SizedBox(width: 6),
          _PresetChip(
            label: 'Last 7 Days',
            active: current.preset == RangePreset.week,
            onTap: () => onChanged(DateRange(
              start: today.subtract(const Duration(days: 6)),
              end: today,
              preset: RangePreset.week,
            )),
          ),
          const SizedBox(width: 6),
          _PresetChip(
            label: 'This Month',
            active: current.preset == RangePreset.month,
            onTap: () => onChanged(DateRange(
              start: DateTime(now.year, now.month, 1),
              end: today,
              preset: RangePreset.month,
            )),
          ),
          const SizedBox(width: 6),
          _PresetChip(
            label: current.preset == RangePreset.custom
                ? '${_fmt(current.start)} – ${_fmt(current.end)}'
                : 'Custom Range',
            active: current.preset == RangePreset.custom,
            icon: Icons.date_range_outlined,
            onTap: onCustomPick,
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            if (icon != null) ...[
              Icon(icon,
                  size: 12,
                  color: active
                      ? AppColors.primary
                      : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}