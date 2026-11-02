// lib/features/shifts/widgets/shift_report_actions.dart
import 'package:flutter/material.dart';

import '../../../core/models/shift_report.dart';
import '../../../core/services/shift_report_service.dart';
import '../../../core/services/thermal_print_service.dart';

/// Print (thermal) / Save PDF / Print PDF buttons for a closed shift.
/// [autoPrint] fires one thermal print when the widget first appears.
class ShiftReportActions extends StatefulWidget {
  final ShiftReportData data;
  final Color color;
  final bool dark;
  final bool autoPrint;

  const ShiftReportActions({
    super.key,
    required this.data,
    required this.color,
    this.dark = false,
    this.autoPrint = false,
  });

  @override
  State<ShiftReportActions> createState() => _ShiftReportActionsState();
}

class _ShiftReportActionsState extends State<ShiftReportActions> {
  String? _busy;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _printThermal());
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFE94560) : null,
      ),
    );
  }

  Future<void> _run(String key, Future<String?> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      final msg = await job();
      if (msg != null) _toast(msg);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _printThermal() => _run('print', () async {
    await ThermalPrintService.printShiftReport(widget.data);
    return null;
  });

  Future<void> _savePdf() => _run('save', () async {
    final path = await ShiftReportService.savePdf(widget.data);
    return 'PDF saved: $path';
  });

  Future<void> _printPdf() => _run('pdf', () async {
    await ShiftReportService.printPdf(widget.data);
    return null;
  });

  Widget _btn(String key, IconData icon, String label, VoidCallback onTap) {
    final fg = widget.dark ? Colors.white : widget.color;
    final border =
        widget.dark ? Colors.white.withValues(alpha: 0.2) : widget.color;
    return OutlinedButton.icon(
      onPressed: _busy == null ? onTap : null,
      icon:
          _busy == key
              ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _btn('print', Icons.print_outlined, 'Print', _printThermal),
        _btn('save', Icons.picture_as_pdf_outlined, 'Save PDF', _savePdf),
        _btn('pdf', Icons.local_print_shop_outlined, 'Print PDF', _printPdf),
      ],
    );
  }
}