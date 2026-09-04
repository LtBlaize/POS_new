import 'order.dart';

class OrderPayment {
  final String id;
  final String orderId;
  final String businessId;
  final PaymentMethod method;
  final double amount;
  final String? referenceNumber;
  final DateTime createdAt;

  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.businessId,
    required this.method,
    required this.amount,
    this.referenceNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_id': orderId,
        'business_id': businessId,
        'method': method.value,
        'amount': amount,
        'reference_number': referenceNumber,
        'created_at': createdAt.toIso8601String(),
      };

  factory OrderPayment.fromMap(Map<String, dynamic> m) => OrderPayment(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        businessId: m['business_id'] as String,
        method: PaymentMethodX.fromString(m['method'] as String),
        amount: (m['amount'] as num).toDouble(),
        referenceNumber: m['reference_number'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Lightweight input for a single payment leg entered in the split-payment
/// UI, before it has an id/orderId (those are assigned when persisted).
class PaymentSplitInput {
  final PaymentMethod method;
  final double amount;
  final String? referenceNumber;

  const PaymentSplitInput({
    required this.method,
    required this.amount,
    this.referenceNumber,
  });
}