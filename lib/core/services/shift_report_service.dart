// lib/core/services/shift_report_service.dart
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/shift_report.dart';

class ShiftReportService {
  static const _mm = PdfPageFormat.mm;

  /// 58mm roll: fixed width, height grows with the content.
  /// 4mm side margins leave ~50mm, safely inside a 58mm printer's print area.
  static const _format = PdfPageFormat(
    58 * _mm,
    double.infinity,
    marginLeft: 4 * _mm,
    marginRight: 4 * _mm,
    marginTop: 4 * _mm,
    marginBottom: 6 * _mm,
  );

  // Built-in PDF fonts are Latin-1 only; replace anything else.
  static String _c(String s) => s
      .replaceAll('₱', 'PHP ')
      .replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF]'), '?');

  static String _fileName(ShiftReportData d) {
    final t = d.shift.closedAt ?? d.shift.openedAt;
    String p(int n) => n.toString().padLeft(2, '0');
    final who = d.shift.staffName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'shift_report_${who}_${t.year}${p(t.month)}${p(t.day)}_${p(t.hour)}${p(t.minute)}';
  }

  static Future<Uint8List> buildPdf(ShiftReportData d) async {
    final reg = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();

    pw.TextStyle st(double size, {bool b = false}) =>
        pw.TextStyle(font: b ? bold : reg, fontSize: size);

    pw.Widget row(ReportRow r) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(_c(r.label), style: st(8, b: r.bold))),
          pw.SizedBox(width: 4),
          pw.Text(_c(r.value), style: st(8, b: r.bold)),
        ],
      ),
    );

    pw.Widget divider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Divider(
        thickness: 0.5,
        height: 1,
        borderStyle: pw.BorderStyle.dashed,
      ),
    );

    pw.Widget centered(String t, double size, {bool b = false}) => pw.Center(
      child: pw.Text(
        _c(t),
        textAlign: pw.TextAlign.center,
        style: st(size, b: b),
      ),
    );

    final doc = pw.Document(title: _fileName(d), author: 'FluxPoint');
    doc.addPage(
      pw.Page(
        pageFormat: _format,
        build:
            (_) => pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (d.businessName?.trim().isNotEmpty ?? false)
                  centered(d.businessName!.toUpperCase(), 10, b: true),
                if (d.businessAddress?.trim().isNotEmpty ?? false)
                  centered(d.businessAddress!, 7),
                pw.SizedBox(height: 4),
                centered('SHIFT REPORT', 11, b: true),
                divider(),
                ...d.header.map(row),
                for (final sec in d.sections) ...[
                  divider(),
                  pw.Text(sec.title, style: st(8, b: true)),
                  pw.SizedBox(height: 2),
                  ...sec.rows.map(row),
                ],
                if (d.notes != null) ...[
                  divider(),
                  pw.Text('NOTES', style: st(8, b: true)),
                  pw.SizedBox(height: 2),
                  pw.Text(_c(d.notes!), style: st(8)),
                ],
                divider(),
                pw.SizedBox(height: 14),
                pw.Text('Cashier: ______________', style: st(8)),
                pw.SizedBox(height: 14),
                pw.Text('Manager: ______________', style: st(8)),
                pw.SizedBox(height: 8),
                centered(d.printedLabel, 7),
              ],
            ),
      ),
    );
    return doc.save();
  }

  /// Saves the PDF; returns where it went.
  static Future<String> savePdf(ShiftReportData d) async {
    final bytes = await buildPdf(d);
    return FileSaver.instance.saveFile(
      name: _fileName(d),
      bytes: bytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  /// System print dialog (any installed printer, or "Save as PDF").
  static Future<void> printPdf(ShiftReportData d) async {
    final bytes = await buildPdf(d);
    await Printing.layoutPdf(
      name: _fileName(d),
      format: _format,
      onLayout: (_) async => bytes,
    );
  }
}