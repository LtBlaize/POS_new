// lib/core/services/escpos_receipts.dart
//
// Builds ESC/POS bytes with esc_pos_utils_plus (already in your pubspec).
// 58mm paper, Font A = 32 chars per line. Uses "PHP" instead of the peso sign,
// since PC437 (the printer's default code page) has no peso glyph.
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/order.dart';

class EscPosReceipts {
  static const _cols = 32;

  static String _money(num v) => 'PHP ${v.toStringAsFixed(2)}';

  /// Strip anything outside printable ASCII so the printer never gets garbage.
  static String _clean(String s) =>
      s.replaceAll('₱', 'PHP ').replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  static Future<Generator> _gen() async {
    final profile = await CapabilityProfile.load();
    return Generator(PaperSize.mm58, profile);
  }

  /// Left label + right value on one 32-char line.
  static List<int> _line(
    Generator g,
    String left,
    String right, {
    bool bold = false,
  }) {
    left = _clean(left);
    right = _clean(right);
    final space = _cols - right.length;
    if (left.length > space - 1) left = left.substring(0, space - 1);
    return g.text(left.padRight(space) + right, styles: PosStyles(bold: bold));
  }

  static Future<Uint8List> testPage() async {
    final g = await _gen();
    final b = <int>[];
    b.addAll(g.reset());
    b.addAll(
      g.text(
        'FLUXPOINT TEST',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    b.addAll(g.hr());
    b.addAll(g.text('12345678901234567890123456789012')); // must fit 1 line
    b.addAll(_line(g, 'Left', 'Right'));
    b.addAll(_line(g, 'TOTAL', _money(1234.5), bold: true));
    b.addAll(
      g.text('Status: OK', styles: const PosStyles(align: PosAlign.center)),
    );
    b.addAll(g.feed(3));
    b.addAll(g.cut());
    return Uint8List.fromList(b);
  }

  static Future<Uint8List> receipt({
    required Order order,
    required String businessName,
    String? businessAddress,
    String? tableNumber,
    double? tendered,
    double? change,
    bool isBill = false,
  }) async {
    final g = await _gen();
    final b = <int>[];
    b.addAll(g.reset());
    b.addAll(
      g.text(
        _clean(businessName.toUpperCase()),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    if (businessAddress != null) {
      b.addAll(
        g.text(
          _clean(businessAddress),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    b.addAll(g.hr());
    if (tableNumber != null) {
      b.addAll(
        g.text(
          'TABLE $tableNumber',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      );
    }
    b.addAll(g.text('Order #${order.orderNumber}'));
    final d = order.createdAt.toLocal();
    b.addAll(
      g.text(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      ),
    );
    b.addAll(g.hr());
    if (isBill) {
      b.addAll(
        g.text(
          'BILL',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    }

    for (final item in order.items) {
      b.addAll(
        _line(
          g,
          '${item.quantity}x ${item.product.name}',
          _money(item.total),
          bold: item.isPromo,
        ),
      );
      if (item.isPromo) {
        for (final c in item.promoComponents!) {
          final n =
              c.variantName != null
                  ? '${c.productName} (${c.variantName})'
                  : c.productName;
          b.addAll(g.text(_clean('  ${c.quantity}x $n')));
        }
      }
    }

    b.addAll(g.hr());
    if (!isBill) b.addAll(_line(g, 'Subtotal', _money(order.subtotal)));
    if (order.taxAmount > 0) b.addAll(_line(g, 'VAT', _money(order.taxAmount)));
    if (order.discountAmount > 0) {
      b.addAll(_line(g, 'Discount', '-${_money(order.discountAmount)}'));
    }
    if (order.tipAmount > 0) b.addAll(_line(g, 'Tip', _money(order.tipAmount)));
    b.addAll(_line(g, 'TOTAL', _money(order.totalAmount), bold: true));

    if (!isBill) {
      b.addAll(g.hr());
      b.addAll(_line(g, 'Payment', order.paymentMethod?.name ?? 'cash'));
      if (tendered != null) b.addAll(_line(g, 'Tendered', _money(tendered)));
      if (change != null) b.addAll(_line(g, 'Change', _money(change)));
      if (order.referenceNumber != null) {
        b.addAll(_line(g, 'Ref#', order.referenceNumber!));
      }
    }

    b.addAll(g.hr());
    b.addAll(
      g.text(
        isBill ? 'This is not an official receipt.' : 'Official Receipt',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    b.addAll(
      g.text('Thank you!', styles: const PosStyles(align: PosAlign.center)),
    );
    b.addAll(g.feed(3));
    b.addAll(g.cut());
    return Uint8List.fromList(b);
  }

  /// Real drawer kick (ESC p), not a blank PDF.
  static Future<Uint8List> drawerKick() async {
    final g = await _gen();
    return Uint8List.fromList(g.drawer());
  }
}
