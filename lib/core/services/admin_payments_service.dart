// lib/core/services/admin_payments_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_subscription_service.dart' show AdminActionException;

class AdminPaymentsService {
  final _client = Supabase.instance.client;

  Future<void> recordManualPayment({
    required String businessId,
    required double amount,
    String currency = 'PHP',
    required String status,
    String? reference,
    String? reason,
  }) async {
    final res = await _client.functions.invoke(
      'admin-record-payment',
      body: {
        'business_id': businessId,
        'amount': amount,
        'currency': currency,
        'status': status,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw AdminActionException(data['error'] as String);
    }
  }
}

final adminPaymentsServiceProvider = Provider<AdminPaymentsService>((ref) {
  return AdminPaymentsService();
});