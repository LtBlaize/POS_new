//lib/features/tables/open_tab_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpenTab {
  final String orderId;
  final int orderNumber;
  final String tableName;
  final double existingTotal;

  const OpenTab({
    required this.orderId,
    required this.orderNumber,
    required this.tableName,
    required this.existingTotal,
  });
}

/// Non-null while the cashier is adding a new round to an existing order.
final openTabProvider = StateProvider<OpenTab?>((ref) => null);