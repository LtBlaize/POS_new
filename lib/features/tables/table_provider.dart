// lib/features/tables/table_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TableStatus { available, occupied, reserved }

class TableEntry {
  final int number;
  final TableStatus status;
  final String? orderId;

  const TableEntry({
    required this.number,
    this.status = TableStatus.available,
    this.orderId,
  });

  TableEntry copyWith({TableStatus? status, String? orderId}) {
    return TableEntry(
      number: number,
      status: status ?? this.status,
      orderId: orderId ?? this.orderId,
    );
  }
}

class TableNotifier extends StateNotifier<List<TableEntry>> {
  TableNotifier()
      : super(List.generate(
            10, (i) => TableEntry(number: i + 1)));

  void selectTable(int number) {
    // Just tracks which table is active for the POS session
    _selectedTable = number;
  }

  int? _selectedTable;
  int? get selectedTable => _selectedTable;

  void occupyTable(int number, String orderId) {
    state = [
      for (final t in state)
        if (t.number == number)
          t.copyWith(status: TableStatus.occupied, orderId: orderId)
        else
          t,
    ];
  }

  void freeTable(int number) {
    state = [
      for (final t in state)
        if (t.number == number)
          TableEntry(number: number)
        else
          t,
    ];
    if (_selectedTable == number) _selectedTable = null;
  }
}

final tableProvider =
    StateNotifierProvider<TableNotifier, List<TableEntry>>(
        (ref) => TableNotifier());

final selectedTableProvider = Provider<int?>((ref) {
  return ref.watch(tableProvider.notifier).selectedTable;
});