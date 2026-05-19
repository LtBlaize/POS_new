// lib/core/models/void_record.dart

/// Represents a single voided item line from an order.
/// Stored locally in [void_order_items] and synced to Supabase.
class VoidRecord {
  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  final double subtotal;
  final String reason;
  final String voidedByStaffId;
  final String voidedByStaffName;
  final DateTime voidedAt;

  const VoidRecord({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
    required this.reason,
    required this.voidedByStaffId,
    required this.voidedByStaffName,
    required this.voidedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_id': orderId,
        'product_id': productId,
        'product_name': productName,
        'unit_price': unitPrice,
        'quantity': quantity,
        'subtotal': subtotal,
        'reason': reason,
        'voided_by_staff_id': voidedByStaffId,
        'voided_by_staff_name': voidedByStaffName,
        'voided_at': voidedAt.toIso8601String(),
      };

  factory VoidRecord.fromMap(Map<String, dynamic> m) => VoidRecord(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        productId: m['product_id'] as String,
        productName: m['product_name'] as String,
        unitPrice: (m['unit_price'] as num).toDouble(),
        quantity: m['quantity'] as int,
        subtotal: (m['subtotal'] as num).toDouble(),
        reason: m['reason'] as String,
        voidedByStaffId: m['voided_by_staff_id'] as String,
        voidedByStaffName: m['voided_by_staff_name'] as String,
        voidedAt: DateTime.parse(m['voided_at'] as String),
      );
}

/// Standard void reasons shown in the dialog.
const kVoidReasons = [
  'Wrong item ordered',
  'Customer changed mind',
  'Item unavailable',
  'Duplicate entry',
  'Kitchen error',
  'Other',
];