import 'cart_item.dart';

enum OrderType { walkIn, takeOut, delivery }
enum OrderStatus { pending, preparing, ready, completed, cancelled }
enum PaymentMethod { cash, card, gcash, maya }

extension OrderTypeX on OrderType {
  String get value => switch (this) {
    OrderType.walkIn  => 'walk_in',
    OrderType.takeOut => 'take_out',
    OrderType.delivery => 'delivery',
  };
  static OrderType fromString(String v) => switch (v) {
    'take_out'  => OrderType.takeOut,
    'delivery'  => OrderType.delivery,
    _           => OrderType.walkIn,
  };
}

extension OrderStatusX on OrderStatus {
  String get value => switch (this) {
    OrderStatus.pending    => 'pending',
    OrderStatus.preparing  => 'preparing',
    OrderStatus.ready      => 'ready',
    OrderStatus.completed  => 'completed',
    OrderStatus.cancelled  => 'cancelled',
  };
  static OrderStatus fromString(String v) => switch (v) {
    'preparing' => OrderStatus.preparing,
    'ready'     => OrderStatus.ready,
    'completed' => OrderStatus.completed,
    'cancelled' => OrderStatus.cancelled,
    _           => OrderStatus.pending,
  };
}

extension PaymentMethodX on PaymentMethod {
  String get value => switch (this) {
    PaymentMethod.cash  => 'cash',
    PaymentMethod.card  => 'card',
    PaymentMethod.gcash => 'gcash',
    PaymentMethod.maya  => 'maya',
  };
  static PaymentMethod fromString(String v) => switch (v) {
    'card'  => PaymentMethod.card,
    'gcash' => PaymentMethod.gcash,
    'maya'  => PaymentMethod.maya,
    _       => PaymentMethod.cash,
  };
}

class Order {
  final String id;
  final String businessId;
  final String? tableId;
  final String? cashierId;
  final int orderNumber;
  final OrderType orderType;
  final OrderStatus status;
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double totalAmount;
  final PaymentMethod? paymentMethod;
  final double? amountTendered;
  final double? changeAmount;
  final String? notes;
  final DateTime? paidAt;
  final DateTime createdAt;

  // Local-only: populated from order_items join
  final List<CartItem> items;

  const Order({
    required this.id,
    required this.businessId,
    this.tableId,
    this.cashierId,
    required this.orderNumber,
    this.orderType = OrderType.walkIn,
    this.status = OrderStatus.pending,
    required this.subtotal,
    this.taxAmount = 0,
    this.discountAmount = 0,
    required this.totalAmount,
    this.paymentMethod,
    this.amountTendered,
    this.changeAmount,
    this.notes,
    this.paidAt,
    required this.createdAt,
    this.items = const [],
  });

  // Legacy getter used in existing UI
  double get total => totalAmount;

  // ← PASTE copyWith HERE
  Order copyWith({
    String? id,
    String? businessId,
    String? tableId,
    String? cashierId,
    int? orderNumber,
    OrderType? orderType,
    OrderStatus? status,
    double? subtotal,
    double? taxAmount,
    double? discountAmount,
    double? totalAmount,
    PaymentMethod? paymentMethod,
    double? amountTendered,
    double? changeAmount,
    String? notes,
    DateTime? paidAt,
    DateTime? createdAt,
    List<CartItem>? items,
  }) {
    return Order(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      tableId: tableId ?? this.tableId,
      cashierId: cashierId ?? this.cashierId,
      orderNumber: orderNumber ?? this.orderNumber,
      orderType: orderType ?? this.orderType,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountTendered: amountTendered ?? this.amountTendered,
      changeAmount: changeAmount ?? this.changeAmount,
      notes: notes ?? this.notes,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  factory Order.fromMap(Map<String, dynamic> map, {List<CartItem> items = const []}) {
    return Order(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      tableId: map['table_id'] as String?,
      cashierId: map['cashier_id'] as String?,
      orderNumber: map['order_number'] as int,
      orderType: OrderTypeX.fromString(map['order_type'] as String? ?? 'walk_in'),
      status: OrderStatusX.fromString(map['status'] as String? ?? 'pending'),
      subtotal: (map['subtotal'] as num).toDouble(),
      taxAmount: (map['tax_amount'] as num).toDouble(),
      discountAmount: (map['discount_amount'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      paymentMethod: map['payment_method'] != null
          ? PaymentMethodX.fromString(map['payment_method'] as String)
          : null,
      amountTendered: (map['amount_tendered'] as num?)?.toDouble(),
      changeAmount: (map['change_amount'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items,
    );
  }
}