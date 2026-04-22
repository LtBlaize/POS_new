// lib/core/services/receipt_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../../features/auth/auth_provider.dart';

final receiptServiceProvider = Provider<ReceiptService>((ref) {
  return ReceiptService(client: ref.watch(supabaseClientProvider));
});

class ReceiptService {
  final dynamic _client;
  ReceiptService({required dynamic client}) : _client = client;

  Future<String> createReceipt({
    required Order order,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    double taxRate = 0.00,
    String currency = 'PHP',
    String? footerText,
    String? issuedBy,
  }) async {
    final now = DateTime.now();
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final receiptNumber =
        'RCP-$datePart-${order.orderNumber.toString().padLeft(6, '0')}';

    final row = await _client.from('receipts').insert({
      'business_id': order.businessId,
      'order_id': order.id,
      'receipt_number': receiptNumber,
      'subtotal': order.subtotal,
      'tax_amount': order.taxAmount,
      'discount_amount': order.discountAmount,
      'total_amount': order.totalAmount,
      'amount_tendered': order.amountTendered,
      'change_amount': order.changeAmount,
      'payment_method': order.paymentMethod?.value,
      'business_name': businessName,
      'business_address': businessAddress,
      'business_phone': businessPhone,
      'business_email': businessEmail,
      'tax_rate': taxRate,
      'currency': currency,
      'footer_text': footerText,
      'issued_by': issuedBy,
      'issued_at': now.toIso8601String(),
    }).select().single();

    return row['id'] as String;
  }
}