// lib/features/admin/businesses/admin_business_detail_screen.dart
//
// Phase 6/7. /admin/businesses/:id — info, subscription, payments, staff,
// activity, plus the subscription action buttons (Change Plan / Extend /
// Suspend / Reactivate). Change Plan now supports an optional paid-access
// duration alongside the plan itself (Phase 5/8): the RPC treats plan and
// subscription_expires_at as independent — this dialog reflects that by
// letting you set either, both, or neither.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_businesses_providers.dart';
import '../../../core/services/admin_subscription_service.dart';
import '../../../core/utils/subscription_expiry_preview.dart';

class AdminBusinessDetailScreen extends ConsumerWidget {
  final String businessId;
  const AdminBusinessDetailScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(businessDetailProvider(businessId));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Could not load this business', style: TextStyle(color: AdminColors.textMuted)),
      ),
      data: (biz) {
        if (biz == null) {
          return const Center(
            child: Text('Business not found', style: TextStyle(color: AdminColors.textMuted)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  color: AdminColors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Text(biz.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AdminColors.textPrimary)),
                const SizedBox(width: 12),
                _pill(biz.isActive ? 'Active' : 'Inactive', biz.isActive ? 'active' : 'suspended'),
                const SizedBox(width: 8),
                _AccessStatusPill(biz: biz),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth > 900;
              final info = _InfoCard(biz: biz);
              final sub = _SubscriptionCard(biz: biz);
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: info), const SizedBox(width: 16), Expanded(child: sub)],
                );
              }
              return Column(children: [info, const SizedBox(height: 16), sub]);
            }),
            const SizedBox(height: 16),
            _StaffCard(staff: biz.staff),
            const SizedBox(height: 16),
            _PaymentsCard(payments: biz.payments),
            const SizedBox(height: 16),
            _ActivityCard(activity: biz.activity),
          ],
        );
      },
    );
  }
}

Widget _pill(String label, String statusKey) {
  final (bg, fg) = AdminColors.statusPillColors(statusKey);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );
}

/// Small pill next to the business name summarizing trial-vs-paid-vs-neither.
/// Purely a display convenience over the three existing fields — does NOT
/// touch hasCoreAccess or any enforcement logic (that's still Gap A, still
/// open, still gated behind the backfill).
class _AccessStatusPill extends StatelessWidget {
  final BusinessDetail biz;
  const _AccessStatusPill({required this.biz});

  @override
  Widget build(BuildContext context) {
    if (!biz.isActive) return const SizedBox.shrink(); // "Inactive" pill already covers this

    final now = DateTime.now();
    final paidActive = biz.subscriptionExpiresAt != null && biz.subscriptionExpiresAt!.isAfter(now);
    final trialActive = biz.trialEndsAt != null && biz.trialEndsAt!.isAfter(now);

    if (paidActive) {
      return _pill('Paid · through ${_fmtDate(biz.subscriptionExpiresAt!)}', 'active');
    }
    if (trialActive) {
      return _pill('Trial · until ${_fmtDate(biz.trialEndsAt!)}', 'trial');
    }
    return _pill('No active access', 'suspended');
  }
}

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
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AdminColors.textPrimary));
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValueRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label, style: const TextStyle(fontSize: 12, color: AdminColors.textMuted))),
            Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary))),
          ],
        ),
      );
}

// ── Info card ────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final BusinessDetail biz;
  const _InfoCard({required this.biz});
  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Business info'),
            const SizedBox(height: 12),
            _KeyValueRow('Type', biz.businessType),
            _KeyValueRow('Address', biz.address ?? ''),
            _KeyValueRow('Phone', biz.phone ?? ''),
            _KeyValueRow('Email', biz.email ?? ''),
            _KeyValueRow('Currency', biz.currency),
            _KeyValueRow('Timezone', biz.timezone),
            _KeyValueRow('Created', _fmtDate(biz.createdAt)),
          ],
        ),
      );
}

// ── Subscription card ───────────────────────────────────────────────────

class _SubscriptionCard extends ConsumerStatefulWidget {
  final BusinessDetail biz;
  const _SubscriptionCard({required this.biz});
  @override
  ConsumerState<_SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends ConsumerState<_SubscriptionCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(businessDetailProvider(widget.biz.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Done')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AdminColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePlan() async {
    final result = await showDialog<_PlanDurationResult>(
      context: context,
      builder: (_) => _PlanDurationDialog(biz: widget.biz),
    );
    if (result == null) return;
    if (result.plan == widget.biz.subscriptionPlan && result.durationMonths == null) return;

    await _run(() => ref.read(adminSubscriptionServiceProvider).changePlan(
          businessId: widget.biz.id,
          newPlan: result.plan,
          durationMonths: result.durationMonths,
        ));
  }

  Future<void> _extend() async {
    final date = await showDatePicker(
      context: context,
      initialDate: widget.biz.trialEndsAt ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    await _run(() => ref.read(adminSubscriptionServiceProvider).extendTrial(
          businessId: widget.biz.id,
          trialEndsAt: date,
        ));
  }

  Future<void> _toggleActive() async {
    final activate = !widget.biz.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(activate ? 'Reactivate business?' : 'Suspend business?'),
        content: Text(activate
            ? 'This restores ${widget.biz.name}\'s access.'
            : 'This will block ${widget.biz.name} from using the POS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = ref.read(adminSubscriptionServiceProvider);
    await _run(() => activate
        ? service.reactivate(businessId: widget.biz.id)
        : service.suspend(businessId: widget.biz.id));
  }

  @override
  Widget build(BuildContext context) {
    final biz = widget.biz;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Subscription'),
          const SizedBox(height: 12),
          _KeyValueRow('Plan', biz.subscriptionPlan),
          _KeyValueRow('Trial started', biz.trialStartedAt != null ? _fmtDate(biz.trialStartedAt!) : ''),
          _KeyValueRow('Trial ends', biz.trialEndsAt != null ? _fmtDate(biz.trialEndsAt!) : ''),
          _KeyValueRow(
              'Paid through', biz.subscriptionExpiresAt != null ? _fmtDate(biz.subscriptionExpiresAt!) : ''),
          const SizedBox(height: 12),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(onPressed: _changePlan, child: const Text('Change Plan', style: TextStyle(fontSize: 12))),
                OutlinedButton(onPressed: _extend, child: const Text('Extend', style: TextStyle(fontSize: 12))),
                OutlinedButton(
                  onPressed: _toggleActive,
                  child: Text(biz.isActive ? 'Suspend' : 'Reactivate', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Change Plan dialog: two-step (select → preview/confirm) ───────────────

class _PlanDurationResult {
  final String plan;
  final int? durationMonths; // null = "No change"
  const _PlanDurationResult({required this.plan, required this.durationMonths});
}

const _durationOptions = <int?>[null, 1, 3, 6, 12]; // null = "No change"

String _durationLabel(int? months) => months == null ? 'No change' : '$months month${months == 1 ? '' : 's'}';

class _PlanDurationDialog extends StatefulWidget {
  final BusinessDetail biz;
  const _PlanDurationDialog({required this.biz});

  @override
  State<_PlanDurationDialog> createState() => _PlanDurationDialogState();
}

class _PlanDurationDialogState extends State<_PlanDurationDialog> {
  late String _plan = widget.biz.subscriptionPlan;
  int? _duration; // starts as "No change"
  bool _preview = false;

  // Mirrors the Edge Function's ALLOWED_PLANS list (starter/growth/pro).
  // Keep these in sync — see the Edge Function's own comment about this
  // being duplicated deliberately.
  static const _plans = ['starter', 'growth', 'pro'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_preview ? 'Confirm change' : 'Change plan'),
      content: SizedBox(
        width: 360,
        child: _preview ? _buildPreview() : _buildSelect(),
      ),
      actions: _preview
          ? [
              TextButton(onPressed: () => setState(() => _preview = false), child: const Text('Back')),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _PlanDurationResult(plan: _plan, durationMonths: _duration),
                ),
                child: const Text('Confirm'),
              ),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: () => setState(() => _preview = true), child: const Text('Next')),
            ],
    );
  }

  Widget _buildSelect() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Plan', style: TextStyle(fontSize: 12, color: AdminColors.textMuted)),
          ..._plans.map((p) => RadioListTile<String>(
                dense: true,
                title: Text(p),
                value: p,
                groupValue: _plan,
                onChanged: (v) => setState(() => _plan = v!),
              )),
          const Divider(height: 24),
          const Text('Paid access duration', style: TextStyle(fontSize: 12, color: AdminColors.textMuted)),
          const SizedBox(height: 4),
          ..._durationOptions.map((d) => RadioListTile<int?>(
                dense: true,
                title: Text(_durationLabel(d)),
                value: d,
                groupValue: _duration,
                onChanged: (v) => setState(() => _duration = v),
              )),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final planChanged = _plan != widget.biz.subscriptionPlan;
    final hadNoExpiry = widget.biz.subscriptionExpiresAt == null;

    // Client-side only, for display — NOT authoritative. The RPC recomputes
    // this server-side against the DB's clock when it actually runs.
    final previewExpiry = SubscriptionExpiryPreview.calculate(
      currentExpiresAt: widget.biz.subscriptionExpiresAt,
      durationMonths: _duration,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValueRow('Plan', planChanged ? '${widget.biz.subscriptionPlan} → $_plan' : _plan),
        _KeyValueRow('Duration', _durationLabel(_duration)),
        _KeyValueRow(
          'Expires',
          _duration == null
              ? (widget.biz.subscriptionExpiresAt != null
                  ? '${_fmtDate(widget.biz.subscriptionExpiresAt!)} (unchanged)'
                  : 'Not set (unchanged)')
              : previewExpiry != null
                  ? '${_fmtDate(previewExpiry)} (preview only)'
                  : '',
        ),
        if (_duration == null && hadNoExpiry) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminColors.warning.withValues(alpha: 0.4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AdminColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This business has no paid access period set. With no duration selected, '
                    'this will only change the plan — it will not grant paid access.',
                    style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Staff card ───────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final List<StaffSummary> staff;
  const _StaffCard({required this.staff});
  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Staff'),
            const SizedBox(height: 12),
            if (staff.isEmpty)
              const Text('No staff members', style: TextStyle(fontSize: 13, color: AdminColors.textMuted))
            else
              ...staff.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(s.name, style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary)),
                        ),
                        Text(s.role, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                        const SizedBox(width: 12),
                        _pill(s.isActive ? 'Active' : 'Inactive', s.isActive ? 'active' : 'suspended'),
                      ],
                    ),
                  )),
          ],
        ),
      );
}

// ── Payments card ────────────────────────────────────────────────────────

class _PaymentsCard extends StatelessWidget {
  final List<dynamic> payments; // RecentPayment, kept dynamic to avoid a cross-import cycle here
  const _PaymentsCard({required this.payments});
  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Payments'),
            const SizedBox(height: 12),
            if (payments.isEmpty)
              const Text('No payments recorded', style: TextStyle(fontSize: 13, color: AdminColors.textMuted))
            else
              ...payments.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${p.provider} · ${p.currency} ${p.amount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary)),
                        ),
                        Text(_fmtDate(p.createdAt),
                            style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                        const SizedBox(width: 12),
                        _pill(p.status, p.status),
                      ],
                    ),
                  )),
          ],
        ),
      );
}

// ── Activity card ────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final List<dynamic> activity; // AdminActivityEntry
  const _ActivityCard({required this.activity});
  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Activity on this business'),
            const SizedBox(height: 12),
            if (activity.isEmpty)
              const Text('No admin activity logged for this business',
                  style: TextStyle(fontSize: 13, color: AdminColors.textMuted))
            else
              ...activity.map((a) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${a.adminRole} (${a.adminIdShort}…) ${a.action}',
                              style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary)),
                        ),
                        Text(_fmtDate(a.createdAt),
                            style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                      ],
                    ),
                  )),
          ],
        ),
      );
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';