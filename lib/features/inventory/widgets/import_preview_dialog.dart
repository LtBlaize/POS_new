// lib/features/inventory/widgets/import_preview_dialog.dart
import 'package:flutter/material.dart';
import '../../../shared/widgets/app_colors.dart';
import '../inventory_import_service.dart';

class ImportPreviewDialog extends StatefulWidget {
  final ImportPreview preview;
  final void Function() onConfirm;

  const ImportPreviewDialog({
    super.key,
    required this.preview,
    required this.onConfirm,
  });

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  bool _showErrors = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final hasErrors = p.errors.isNotEmpty;
    final hasValid = p.valid.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.upload_file_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text('Import Preview',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary pills ──────────────────────────────────
                    Row(
                      children: [
                        _SummaryPill(
                          label: 'New',
                          count: p.newCount,
                          color: AppColors.success,
                          icon: Icons.add_circle_outline,
                        ),
                        const SizedBox(width: 8),
                        _SummaryPill(
                          label: 'Update',
                          count: p.updateCount,
                          color: AppColors.info,
                          icon: Icons.edit_outlined,
                        ),
                        if (hasErrors) ...[
                          const SizedBox(width: 8),
                          _SummaryPill(
                            label: 'Skipped',
                            count: p.errors.length,
                            color: AppColors.danger,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Valid rows preview ─────────────────────────────
                    if (hasValid) ...[
                      const Text('Rows to import',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            // Table header
                            _TableHeader(),
                            const Divider(height: 1),
                            // Rows (max 8 visible, then scroll)
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 280),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: p.valid.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) =>
                                    _PreviewRow(row: p.valid[i]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Errors ─────────────────────────────────────────
                    if (hasErrors) ...[
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showErrors = !_showErrors),
                        child: Row(
                          children: [
                            Icon(
                              _showErrors
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${p.errors.length} row${p.errors.length > 1 ? 's' : ''} skipped — tap to ${_showErrors ? 'hide' : 'show'}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      if (_showErrors) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha:0.04),
                            border: Border.all(
                                color: AppColors.danger.withValues(alpha:0.2)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: p.errors
                                .map((e) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Row ${e.rowNumber}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.danger)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(e.message,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.danger)),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ],

                    if (!hasValid)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text('No valid rows to import.',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Action buttons ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: hasValid
                          ? () {
                              Navigator.of(context).pop();
                              widget.onConfirm();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.divider,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        hasValid
                            ? 'Import ${p.valid.length} product${p.valid.length > 1 ? 's' : ''}'
                            : 'Nothing to import',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Table helpers ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 46, child: Text('', style: _hStyle)),
          Expanded(child: Text('NAME', style: _hStyle)),
          SizedBox(width: 72, child: Text('PRICE', textAlign: TextAlign.right, style: _hStyle)),
          SizedBox(width: 72, child: Text('COST', textAlign: TextAlign.right, style: _hStyle)),
          SizedBox(width: 56, child: Text('STOCK', textAlign: TextAlign.right, style: _hStyle)),
        ],
      ),
    );
  }

  static const _hStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.4,
  );
}

class _PreviewRow extends StatelessWidget {
  final ImportRow row;
  const _PreviewRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: row.isUpdate
                    ? AppColors.info.withValues(alpha:0.1)
                    : AppColors.success.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                row.isUpdate ? 'UPD' : 'NEW',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: row.isUpdate ? AppColors.info : AppColors.success),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (row.category != null)
                  Text(row.category!,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
          SizedBox(
            width: 72,
            child: Text('₱${row.price.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary)),
          ),
          SizedBox(
            width: 72,
            child: Text(
              row.costPrice > 0 ? '₱${row.costPrice.toStringAsFixed(2)}' : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: row.costPrice > 0
                      ? AppColors.textPrimary
                      : AppColors.textSecondary),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text('${row.stockQuantity}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SummaryPill({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$count $label',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}