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
  final CreditTxType type;
  final double amount;
  final String? note;
  final String? orderId;
  final DateTime createdAt;

  const CreditTransaction({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    this.note,
    this.orderId,
    required this.createdAt,
  });
}