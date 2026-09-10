// lib/features/admin/payments/admin_payments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import '../../../core/services/admin_payments_service.dart';
import '../../../core/services/admin_subscription_service.dart';
import 'admin_payments_providers.dart';

// Keep in sync with the subscription_plan enum / pricing elsewhere in the
// admin dashboard (starter/growth/pro, ₱499/₱799/₱1,299).
const kPlanPrices = <String, double>{
  'starter': 499,
  'growth': 799,
  'pro': 1299,
};

class AdminPaymentsScreen extends ConsumerWidget {
  const AdminPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AdminColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Record payment'),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _RecordPaymentDialog(),
        ),
      ),
      body: Column(
        children: [
          const _PaymentFilterBar(),
          const Divider(height: 1, color: AdminColors.divider),
          const Expanded(child: _PaymentListBody()),
          const _PaymentPaginationBar(),
        ],
      ),
    );
  }
}

// ── Filters ──────────────────────────────────────────────────────────────

class _PaymentFilterBar extends ConsumerStatefulWidget {
  const _PaymentFilterBar();
  @override
  ConsumerState<_PaymentFilterBar> createState() => _PaymentFilterBarState();
}

class _PaymentFilterBarState extends ConsumerState<_PaymentFilterBar> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: ref.read(paymentFilterProvider).businessSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _update(PaymentFilter Function(PaymentFilter) fn) {
    ref.read(paymentFilterProvider.notifier).update(fn);
    ref.read(paymentPageProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(paymentFilterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => _update((f) => f.copyWith(businessSearch: v)),
              decoration: InputDecoration(
                hintText: 'Search business…',
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
          _dropdown(
            value: filter.status,
            hint: 'All statuses',
            items: const ['pending', 'completed', 'failed', 'refunded'],
            onChanged: (v) => _update((f) => f.copyWith(status: v)),
          ),
          _dropdown(
            value: filter.provider,
            hint: 'All providers',
            items: const ['manual', 'paymongo'],
            onChanged: (v) => _update((f) => f.copyWith(provider: v)),
          ),
          if (filter.status != null || filter.provider != null || filter.businessSearch.isNotEmpty)
            TextButton(
              onPressed: () {
                _searchCtrl.clear();
                _update((_) => const PaymentFilter());
              },
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

// ── List ─────────────────────────────────────────────────────────────────

class _PaymentListBody extends ConsumerWidget {
  const _PaymentListBody();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentListProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Could not load payments', style: TextStyle(color: AdminColors.textMuted)),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Center(
            child: Text('No payments match these filters', style: TextStyle(color: AdminColors.textMuted)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: page.items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AdminColors.divider),
          itemBuilder: (context, i) {
            final p = page.items[i];
            final (bg, fg) = AdminColors.statusPillColors(p.status);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(p.businessName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${p.currency} ${p.amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(p.provider, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_fmtDate(p.createdAt),
                        style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(p.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ── Pagination ───────────────────────────────────────────────────────────

class _PaymentPaginationBar extends ConsumerWidget {
  const _PaymentPaginationBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(paymentPageProvider);
    final async = ref.watch(paymentListProvider);
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
              Text('${result.totalCount} payments', style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    color: page > 0 ? AdminColors.textPrimary : AdminColors.textMuted,
                    onPressed: page > 0 ? () => ref.read(paymentPageProvider.notifier).state = page - 1 : null,
                  ),
                  Text('Page ${page + 1} of $totalPages', style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color: page + 1 < totalPages ? AdminColors.textPrimary : AdminColors.textMuted,
                    onPressed: page + 1 < totalPages ? () => ref.read(paymentPageProvider.notifier).state = page + 1 : null,
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

// ── Record payment dialog ───────────────────────────────────────────────

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog();
  @override
  ConsumerState<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  final _businessCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  BusinessOption? _selectedBusiness;
  String? _selectedPlan; // 'starter' | 'growth' | 'pro'
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _businessCtrl.dispose();
    _referenceCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final biz = _selectedBusiness;
    final plan = _selectedPlan;
    if (biz == null) {
      setState(() => _error = 'Select a business first');
      return;
    }
    if (plan == null) {
      setState(() => _error = 'Select a plan');
      return;
    }
    final amount = kPlanPrices[plan]!;

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Two separate Edge Function calls, not one atomic operation server-side.
    // If the plan-change call fails after the payment already succeeded,
    // surface that specifically rather than folding both into one generic
    // error — the payment is still recorded either way, only the plan/expiry
    // update is left undone.
    try {
      await ref.read(adminPaymentsServiceProvider).recordManualPayment(
            businessId: biz.id,
            amount: amount,
            status: 'completed',
            reference: _referenceCtrl.text.trim(),
            reason: _reasonCtrl.text.trim(),
          );
    } catch (e) {
      setState(() {
        _error = 'Payment failed: $e';
        _submitting = false;
      });
      return;
    }

    try {
      await ref.read(adminSubscriptionServiceProvider).changePlan(
            businessId: biz.id,
            newPlan: plan,
            durationMonths: 1,
          );
      ref.invalidate(paymentListProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error =
            'Payment recorded, but applying the plan failed: $e. Use Change Plan on the business to finish this manually.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessesAsync = ref.watch(allBusinessOptionsProvider);
    final allBusinesses = businessesAsync.value ?? const <BusinessOption>[];

    return AlertDialog(
      title: const Text('Record manual payment'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Autocomplete<BusinessOption>(
              displayStringForOption: (b) => b.name,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return allBusinesses; // shows the full list as soon as the field is tapped
                final starts = <BusinessOption>[];
                final contains = <BusinessOption>[];
                for (final b in allBusinesses) {
                  final name = b.name.toLowerCase();
                  if (name.startsWith(q)) {
                    starts.add(b);
                  } else if (name.contains(q)) {
                    contains.add(b);
                  }
                }
                return [...starts, ...contains]; // prefix matches ranked above mid-string matches
              },
              onSelected: (b) => setState(() => _selectedBusiness = b),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Business',
                    hintText: businessesAsync.isLoading ? 'Loading businesses…' : 'Tap to browse or type to filter…',
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Plan', style: TextStyle(fontSize: 12, color: AdminColors.textMuted)),
            const SizedBox(height: 8),
            Row(
              children: kPlanPrices.entries.map((e) {
                final selected = _selectedPlan == e.key;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selectedPlan = e.key),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: selected ? AdminColors.infoBg : AdminColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? AdminColors.primary : AdminColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              e.key[0].toUpperCase() + e.key.substring(1),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected ? AdminColors.primary : AdminColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('₱${e.value.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenceCtrl,
              decoration: const InputDecoration(labelText: 'Reference (optional)', hintText: 'e.g. bank transfer ref #'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Record'),
        ),
      ],
    );
  }
}