// lib/features/admin/dashboard/admin_dashboard_screen.dart
//
// Phase 5. Replaces AdminPlaceholderScreen for '/admin' and '/admin/dashboard'
// only — every other admin route still resolves to the placeholder until its
// own phase lands (see app_router.dart diff below).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_dashboard_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardKpisProvider);
        ref.invalidate(dashboardRevenueChartProvider);
        ref.invalidate(dashboardSubscriptionBreakdownProvider);
        ref.invalidate(dashboardRecentBusinessesProvider);
        ref.invalidate(dashboardRecentPaymentsProvider);
        ref.invalidate(dashboardActivityFeedProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _KpiRow(),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 900;
            final chart = const _RevenueChartCard();
            final breakdown = const _SubscriptionBreakdownCard();
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: chart),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: breakdown),
                ],
              );
            }
            return Column(children: [chart, const SizedBox(height: 16), breakdown]);
          }),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 900;
            final biz = const _RecentBusinessesCard();
            final pay = const _RecentPaymentsCard();
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: biz),
                  const SizedBox(width: 16),
                  Expanded(child: pay),
                ],
              );
            }
            return Column(children: [biz, const SizedBox(height: 16), pay]);
          }),
          const SizedBox(height: 24),
          const _ActivityFeedCard(),
        ],
      ),
    );
  }
}

// ── Shared card shell ───────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminColors.border),
        ),
        child: child,
      );
}

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AdminColors.textPrimary,
        ),
      );
}

// ── KPI row ──────────────────────────────────────────────────────────────

class _KpiRow extends ConsumerWidget {
  const _KpiRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(dashboardKpisProvider);

    return kpisAsync.when(
      loading: () => const _KpiRowSkeleton(),
      error: (_, __) => const _KpiRowSkeleton(),
      data: (kpis) {
        // "Active Pro" — plan-name assumption flagged in providers file.
        // Falls back to the single largest non-free plan bucket if a plan
        // literally named 'pro' isn't present, so this never silently shows 0
        // just because the enum uses different casing/naming.
        final proCount = kpis.planCounts['pro'] ??
            (kpis.planCounts.entries
                    .where((e) => e.key != 'free')
                    .fold<int>(0, (s, e) => s + e.value));

        final currency = _currencyFmt(kpis.monthlyRevenue);

        final cards = [
          _KpiCard(label: 'Total Businesses', value: '${kpis.totalBusinesses}'),
          _KpiCard(label: 'Active Subscriptions', value: '${kpis.activeSubscriptions}'),
          _KpiCard(label: 'Monthly Revenue', value: currency),
          _KpiCard(label: 'Active Pro', value: '$proCount'),
        ];

        return LayoutBuilder(builder: (context, c) {
          final perRow = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 2 : 1);
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards
                .map((card) => SizedBox(
                      width: (c.maxWidth - (perRow - 1) * 16) / perRow,
                      child: card,
                    ))
                .toList(),
          );
        });
      },
    );
  }
}

String _currencyFmt(double v) {
  // Matches businesses.currency default (PHP) — swap for a real intl
  // formatter if the app already depends on `intl` elsewhere.
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '₱$buf';
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  const _KpiCard({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AdminColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    color: AdminColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _KpiRowSkeleton extends StatelessWidget {
  const _KpiRowSkeleton();
  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 3 ? 16 : 0),
              child: _Card(
                child: Container(height: 58, color: AdminColors.divider),
              ),
            ),
          ),
        ),
      );
}

// ── Revenue chart ────────────────────────────────────────────────────────

class _RevenueChartCard extends ConsumerWidget {
  const _RevenueChartCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartAsync = ref.watch(dashboardRevenueChartProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Revenue — last 6 months'),
          const SizedBox(height: 20),
          chartAsync.when(
            loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const _EmptyState('Could not load revenue data'),
            data: (points) {
              if (points.isEmpty) {
                return const _EmptyState('No payment history yet');
              }
              final maxAmount = points.map((p) => p.amount).fold<double>(0, (a, b) => a > b ? a : b);
              return SizedBox(
                height: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: points.map((p) {
                    final h = maxAmount > 0 ? (p.amount / maxAmount) * 120 : 0.0;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              p.amount > 0 ? _currencyFmt(p.amount) : '—',
                              style: const TextStyle(fontSize: 10, color: AdminColors.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: h < 4 && p.amount > 0 ? 4 : h,
                              decoration: BoxDecoration(
                                color: AdminColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_monthLabel(p.month),
                                style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

String _monthLabel(DateTime d) =>
    const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month];

// ── Subscription breakdown ──────────────────────────────────────────────

class _SubscriptionBreakdownCard extends ConsumerWidget {
  const _SubscriptionBreakdownCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownAsync = ref.watch(dashboardSubscriptionBreakdownProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Subscription breakdown'),
          const SizedBox(height: 16),
          breakdownAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const _EmptyState('Could not load breakdown'),
            data: (items) {
              if (items.isEmpty) return const _EmptyState('No businesses yet');
              return Column(
                children: items
                    .map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(b.plan, style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13)),
                                  Text('${b.count} · ${b.pct.toStringAsFixed(0)}%',
                                      style: const TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: b.pct / 100,
                                  minHeight: 6,
                                  backgroundColor: AdminColors.divider,
                                  valueColor: const AlwaysStoppedAnimation(AdminColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Recent businesses / payments ────────────────────────────────────────

class _RecentBusinessesCard extends ConsumerWidget {
  const _RecentBusinessesCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardRecentBusinessesProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Recent businesses'),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const _EmptyState('Could not load businesses'),
            data: (items) => items.isEmpty
                ? const _EmptyState('No businesses yet')
                : Column(
                    children: items
                        .map((b) => _RowTile(
                              title: b.name,
                              subtitle: b.subscriptionPlan,
                              trailing: b.isActive ? 'Active' : 'Inactive',
                              trailingColor: b.isActive ? AdminColors.success : AdminColors.neutral,
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentPaymentsCard extends ConsumerWidget {
  const _RecentPaymentsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardRecentPaymentsProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Recent payments'),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const _EmptyState('Could not load payments'),
            data: (items) => items.isEmpty
                ? const _EmptyState('No payments recorded yet')
                : Column(
                    children: items
                        .map((p) => _RowTile(
                              title: p.businessName,
                              subtitle: '${p.provider} · ${_currencyFmt(p.amount)}',
                              trailing: p.status,
                              trailingColor: AdminColors.statusPillColors(p.status).$2,
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;
  final Color trailingColor;
  const _RowTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.trailingColor,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13)),
                  Text(subtitle, style: const TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Text(trailing, style: TextStyle(color: trailingColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ── Activity feed ────────────────────────────────────────────────────────

class _ActivityFeedCard extends ConsumerWidget {
  const _ActivityFeedCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardActivityFeedProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Activity feed'),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const _EmptyState('Could not load activity'),
            data: (items) => items.isEmpty
                ? const _EmptyState('No admin activity yet')
                : Column(
                    children: items
                        .map((a) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AdminColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                                        children: [
                                          TextSpan(
                                              text: '${a.adminRole} (${a.adminIdShort}…) ',
                                              style: const TextStyle(fontWeight: FontWeight.w600)),
                                          TextSpan(text: a.action),
                                          if (a.targetType != null)
                                            TextSpan(
                                                text: ' · ${a.targetType}${a.targetId != null ? " #${a.targetId}" : ""}',
                                                style: const TextStyle(color: AdminColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Text(_timeAgo(a.createdAt),
                                      style: const TextStyle(fontSize: 11, color: AdminColors.textMuted)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(this.message);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: const TextStyle(color: AdminColors.textMuted, fontSize: 13)),
      );
}