// lib/core/models/credit.dart

class CreditCustomer {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final double totalOwed;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CreditCustomer({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.totalOwed,
    required this.createdAt,
    required this.updatedAt,
  });

  CreditCustomer copyWith({double? totalOwed, DateTime? updatedAt}) =>
      CreditCustomer(
        id: id,
        businessId: businessId,
        name: name,
        phone: phone,
        totalOwed: totalOwed ?? this.totalOwed,
        updatedAt: updatedAt ?? this.updatedAt,
        createdAt: createdAt,
      );
}

enum CreditTxType { credit, payment }

class CreditTransaction {
  final String id;
  final String customerId;
  final String businessId;
  final CreditTxType type;
  final double amount;
  final double? amountRemaining; // null for payments, tracks unpaid for credits
  final bool isSettled;
  final DateTime? settledAt;
  final String? note;
  final String? orderId;
  final DateTime createdAt;

  const CreditTransaction({
    required this.id,
    required this.customerId,
    required this.businessId,
    required this.type,
    required this.amount,
    this.amountRemaining,
    this.isSettled = false,
    this.settledAt,
    this.note,
    this.orderId,
    required this.createdAt,
  });

  // For credit transactions: how much has been paid off
  double get amountPaid =>
      type == CreditTxType.credit ? amount - (amountRemaining ?? amount) : 0;

  bool get isPartiallyPaid =>
      type == CreditTxType.credit &&
      amountPaid > 0 &&
      !isSettled;
}

/// Represents how a payment was applied across credit transactions
class CreditSettlement {
  final String paymentTxId;
  final String creditTxId;
  final double amountApplied;

  const CreditSettlement({
    required this.paymentTxId,
    required this.creditTxId,
    required this.amountApplied,
  });
}