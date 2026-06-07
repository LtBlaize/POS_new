// features/reports/widgets/export_button.dart
//
// On Windows / Linux / macOS  → saves directly to the user's Downloads folder
//                               and shows a snackbar with the path.
// On iOS / Android            → opens the system share sheet as before.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../report_excel_service.dart';
import '../reports_providers.dart';
import '../../../shared/widgets/app_colors.dart';

class ExportButton extends ConsumerStatefulWidget {
  final DateTime date;
  final DateRange? dateRange;
  final DailyReport? dailyReport;
  final List<ShiftEntry>? shifts;

  const ExportButton({
    super.key,
    required this.date,
    this.dateRange,
    required this.dailyReport,
    required this.shifts,
  });

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _busy = false;

  // Returns true if we're running on a desktop OS.
  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> _export() async {
    final report = widget.dailyReport;
    final shifts = widget.shifts;

    if (report == null || shifts == null) {
      _showSnack('Report data is still loading — try again in a moment.');
      return;
    }

    if (report.totalOrders == 0 && shifts.isEmpty) {
      _showSnack('Nothing to export — no data for this date.');
      return;
    }

    setState(() => _busy = true);

    try {
      final service = ref.read(reportExcelServiceProvider);
      final tempPath = await service.buildAndSave(
        date: widget.date,
        dateRange: widget.dateRange,
        dailyReport: report,
        shiftEntries: shifts,
      );

      if (_isDesktop) {
        await _saveToDownloads(tempPath);
      } else {
        await _shareFile(tempPath);
      }
    } catch (e, st) {
      debugPrint('[ExportButton] export failed: $e\n$st');
      _showSnack('Export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Desktop: copy to Downloads and notify ──────────────────────────────────

  Future<void> _saveToDownloads(String tempPath) async {
    // getDownloadsDirectory() works on Windows, macOS, Linux.
    final downloadsDir = await getDownloadsDirectory();
    final dir = downloadsDir ?? await getApplicationDocumentsDirectory();

    final fileName = _fileName(widget.date);
    final destPath = '${dir.path}${Platform.pathSeparator}$fileName';

    await File(tempPath).copy(destPath);
    _deleteTempFile(tempPath);

    _showSnack('Saved to ${dir.path}${Platform.pathSeparator}$fileName');
  }

  // ── Mobile: share sheet ────────────────────────────────────────────────────

  Future<void> _shareFile(String tempPath) async {
    final xFile = XFile(
      tempPath,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      name: _fileName(widget.date),
    );

    final result = await Share.shareXFiles(
      [xFile],
      subject: _fileName(widget.date),
    );

    if (result.status != ShareResultStatus.unavailable) {
      _deleteTempFile(tempPath);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _deleteTempFile(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _fileName(DateTime d) {
    final range = widget.dateRange;
    if (range != null && !range.isSingleDay) {
      final s = range.start;
      final e = range.end;
      return 'report_${s.year}-${s.month.toString().padLeft(2, '0')}-'
          '${s.day.toString().padLeft(2, '0')}_to_'
          '${e.year}-${e.month.toString().padLeft(2, '0')}-'
          '${e.day.toString().padLeft(2, '0')}.xlsx';
    }
    return 'report_${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}.xlsx';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isReady = widget.dailyReport != null && widget.shifts != null;
    final enabled = isReady && !_busy;

    return Tooltip(
      message: _isDesktop ? 'Save to Downloads' : 'Export to Excel',
      child: InkWell(
        onTap: enabled ? _export : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? AppColors.divider
                  : AppColors.divider.withValues(alpha:0.4),
            ),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.primary),
                  ),
                )
              : Icon(
                  // Show a download icon on desktop, share icon on mobile
                  _isDesktop
                      ? Icons.file_download_outlined
                      : Icons.ios_share_rounded,
                  size: 16,
                  color: enabled
                      ? AppColors.textSecondary
                      : AppColors.textSecondary.withValues(alpha:0.3),
                ),
        ),
      ),
    );
  }
}