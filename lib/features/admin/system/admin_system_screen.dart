// lib/features/admin/system/admin_system_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_system_providers.dart';

class AdminSystemScreen extends ConsumerWidget {
  const AdminSystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(systemChecksProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(systemChecksProvider),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('System health',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AdminColors.textPrimary)),
              TextButton.icon(
                onPressed: () => ref.invalidate(systemChecksProvider),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-check', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Could not run system checks', style: TextStyle(color: AdminColors.textMuted)),
              ),
            ),
            data: (checks) => Column(
              children: checks.map((c) => _CheckRow(check: c)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final SystemCheck check;
  const _CheckRow({required this.check});

  (Color, Color, String) get _statusVisuals => switch (check.status) {
        CheckStatus.ok => (AdminColors.successBg, AdminColors.success, 'Operational'),
        CheckStatus.degraded => (AdminColors.warningBg, AdminColors.warning, 'Degraded'),
        CheckStatus.down => (AdminColors.dangerBg, AdminColors.danger, 'Down'),
        CheckStatus.notConfigured => (AdminColors.neutralBg, AdminColors.neutral, 'Not configured'),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _statusVisuals;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                const SizedBox(height: 2),
                Text(check.detail, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
              ],
            ),
          ),
          if (check.latency != null) ...[
            Text('${check.latency!.inMilliseconds}ms',
                style: const TextStyle(fontSize: 11, color: AdminColors.textMuted)),
            const SizedBox(width: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
  }
}