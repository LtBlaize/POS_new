// lib/features/admin/payments/admin_payments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import '../../../core/services/admin_payments_service.dart';
import 'admin_payments_providers.dart';

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
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  BusinessOption? _selectedBusiness;
  String _status = 'completed';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _businessCtrl.dispose();
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final biz = _selectedBusiness;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (biz == null) {
      setState(() => _error = 'Select a business first');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(adminPaymentsServiceProvider).recordManualPayment(
            businessId: biz.id,
            amount: amount,
            status: _status,
            reference: _referenceCtrl.text.trim(),
            reason: _reasonCtrl.text.trim(),
          );
      ref.invalidate(paymentListProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              optionsBuilder: (value) async {
                if (value.text.trim().length < 2) return const [];
                return ref.read(businessSearchProvider(value.text).future);
              },
              onSelected: (b) => setState(() => _selectedBusiness = b),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Business', hintText: 'Search by name…'),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (PHP)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
                DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'completed'),
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