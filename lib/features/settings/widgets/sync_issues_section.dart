// lib/features/settings/widgets/sync_issues_section.dart
//
// Shows dead-lettered sync_queue entries (operations that exhausted all
// retries) so a failed payment/order sync is visible instead of vanishing.
// POS device only — sync_queue only exists on the cashier.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_queue_service.dart';
import '../../../shared/widgets/app_colors.dart';

class SyncIssuesSection extends ConsumerStatefulWidget {
  const SyncIssuesSection({super.key});

  @override
  ConsumerState<SyncIssuesSection> createState() => _SyncIssuesSectionState();
}

class _SyncIssuesSectionState extends ConsumerState<SyncIssuesSection> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ref.read(syncQueueServiceProvider).getFailedEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _retry(int id) async {
    setState(() => _busyIds.add(id));
    await ref.read(syncQueueServiceProvider).retryFailedEntry(id);
    await _load();
    if (!mounted) return;
    setState(() => _busyIds.remove(id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Retrying...'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _discard(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this entry?'),
        content: const Text(
            'This change will be permanently dropped and will never sync to the server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyIds.add(id));
    await ref.read(syncQueueServiceProvider).discardFailedEntry(id);
    await _load();
    if (!mounted) return;
    setState(() => _busyIds.remove(id));
  }

  String _describe(Map<String, dynamic> entry) {
    final op = entry['operation'] as String;
    return switch (op) {
      'insert_order' => 'New order',
      'update_order_status' => 'Order status update',
      'process_payment' => 'Payment',
      'insert_receipt' => 'Receipt',
      'adjust_stock' || 'adjust_variant_stock' => 'Stock adjustment',
      'insert_order_items' => 'Order items',
      'void_order_item' => 'Voided item',
      'void_order' => 'Voided order',
      'record_credit_payment' => 'Credit payment',
      'upload_product_image' => 'Product photo upload',
      'insert_kitchen_ticket' => 'Kitchen ticket',
      'add_staff' || 'update_staff' || 'delete_staff' => 'Staff change',
      _ => op,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 15, color: Colors.red),
            const SizedBox(width: 6),
            const Text(
              'SYNC ISSUES',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3),
            ),
            if (_entries.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_entries.length}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade700),
                ),
              ),
            ],
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              color: AppColors.textSecondary,
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nothing failed to sync. All changes have reached the server.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'These changes could not be sent to the server after repeated attempts. '
              'Retry once the issue is resolved, or discard to drop them permanently.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          ..._entries.map((e) => _FailedEntryTile(
                title: _describe(e),
                tableName: e['table_name'] as String,
                recordId: e['record_id'] as String,
                lastError: e['last_error'] as String?,
                retries: e['retries'] as int,
                createdAt: e['created_at'] as String,
                busy: _busyIds.contains(e['id'] as int),
                onRetry: () => _retry(e['id'] as int),
                onDiscard: () => _discard(e['id'] as int),
              )),
        ],
      ],
    );
  }
}

class _FailedEntryTile extends StatelessWidget {
  final String title;
  final String tableName;
  final String recordId;
  final String? lastError;
  final int retries;
  final String createdAt;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  const _FailedEntryTile({
    required this.title,
    required this.tableName,
    required this.recordId,
    required this.lastError,
    required this.retries,
    required this.createdAt,
    required this.busy,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final shortId =
        recordId.length > 8 ? recordId.substring(0, 8) : recordId;
    final when = DateTime.tryParse(createdAt);
    final whenLabel = when == null
        ? ''
        : '${when.month}/${when.day} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              Text(
                whenLabel,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$tableName · #$shortId · $retries failed attempt${retries == 1 ? '' : 's'}',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontFamily: 'monospace'),
          ),
          if (lastError != null && lastError!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lastError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onRetry,
                  icon: busy
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Retry', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onDiscard,
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  label:
                      const Text('Discard', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}