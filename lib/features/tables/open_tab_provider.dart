import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpenTab {
  final String orderId;
  final int orderNumber;
  /// Null for a ticket with no table (walk-in / takeout).
  final String? tableName;
  final String? customerName;
  final double existingTotal;

  const OpenTab({
    required this.orderId,
    required this.orderNumber,
    this.tableName,
    this.customerName,
    required this.existingTotal,
  });

  String get label => tableName != null
      ? 'Table $tableName'
      : (customerName?.isNotEmpty == true ? customerName! : 'Walk-in ticket');
}

/// Non-null while the cashier is adding a new round to an existing order.
final openTabProvider = StateProvider<OpenTab?>((ref) => null);