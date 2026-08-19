// lib/features/admin/plans/admin_plans_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_plans_providers.dart';
import 'dart:convert';

class AdminPlansScreen extends ConsumerWidget {
  const AdminPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subscriptionPlansProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AdminColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _PlanFormDialog(plan: null),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Could not load plans', style: TextStyle(color: AdminColors.textMuted)),
        ),
        data: (plans) {
          if (plans.isEmpty) {
            return const Center(
              child: Text('No plans configured yet', style: TextStyle(color: AdminColors.textMuted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: plans.length,
            itemBuilder: (context, i) => _PlanCard(plan: plans[i]),
          );
        },
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  final SubscriptionPlan plan;
  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (bg, fg) = AdminColors.statusPillColors(plan.isActive ? 'active' : 'suspended');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                const SizedBox(height: 4),
                Text('₱${plan.price.toStringAsFixed(2)} / ${plan.billingInterval}',
                    style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              plan.features.isEmpty ? 'No features set' : jsonEncode(plan.features),
              style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(plan.isActive ? 'Active' : 'Inactive',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AdminColors.textSecondary,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _PlanFormDialog(plan: plan),
            ),
          ),
          Switch(
            value: plan.isActive,
            activeColor: AdminColors.primary,
            onChanged: (v) async {
              try {
                await ref.read(adminPlansServiceProvider).setActive(plan.id, v);
                ref.invalidate(subscriptionPlansProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: AdminColors.danger),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PlanFormDialog extends ConsumerStatefulWidget {
  final SubscriptionPlan? plan; // null = create
  const _PlanFormDialog({required this.plan});

  @override
  ConsumerState<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends ConsumerState<_PlanFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _featuresCtrl;
  late String _interval;
  late bool _isActive;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(text: p?.price.toStringAsFixed(2) ?? '0.00');
    _featuresCtrl = TextEditingController(
      text: p != null && p.features.isNotEmpty
          ? const JsonEncoder.withIndent('  ').convert(p.features)
          : '{}',
    );
    _interval = p?.billingInterval ?? 'monthly';
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price');
      return;
    }

    Map<String, dynamic> features;
    try {
      features = parseFeaturesJson(_featuresCtrl.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    } catch (_) {
      setState(() => _error = 'Features must be valid JSON');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final service = ref.read(adminPlansServiceProvider);
      if (_isEdit) {
        await service.updatePlan(
          id: widget.plan!.id,
          name: name,
          price: price,
          billingInterval: _interval,
          features: features,
          isActive: _isActive,
        );
      } else {
        await service.createPlan(
          name: name,
          price: price,
          billingInterval: _interval,
          features: features,
          isActive: _isActive,
        );
      }
      ref.invalidate(subscriptionPlansProvider);
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
      title: Text(_isEdit ? 'Edit plan' : 'New plan'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Plan name')),
              const SizedBox(height: 12),
              TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price (PHP)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _interval,
                decoration: const InputDecoration(labelText: 'Billing interval'),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                ],
                onChanged: (v) => setState(() => _interval = v ?? 'monthly'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _featuresCtrl,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Features (JSON)',
                  alignLabelWithHint: true,
                  hintText: '{"kitchen": true, "tables": false}',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active', style: TextStyle(fontSize: 13)),
                value: _isActive,
                activeColor: AdminColors.primary,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}