// lib/features/tables/table_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/auth_provider.dart';

enum TableStatus { available, occupied, reserved }

class TableEntry {
  final int number;
  final String? uuid; // actual restaurant_tables.id from Supabase
  final TableStatus status;
  final String? orderId;

  const TableEntry({
    required this.number,
    this.uuid,
    this.status = TableStatus.available,
    this.orderId,
  });

  TableEntry copyWith({
    String? uuid,
    TableStatus? status,
    String? orderId,
    bool clearOrder = false,
  }) {
    return TableEntry(
      number: number,
      uuid: uuid ?? this.uuid,
      status: status ?? this.status,
      orderId: clearOrder ? null : (orderId ?? this.orderId),
    );
  }
}

// ── Table state includes selectedTableNumber so UI rebuilds on selection ──────
class TableState {
  final List<TableEntry> tables;
  final int? selectedTableNumber;
  final bool isLoading;

  const TableState({
    required this.tables,
    this.selectedTableNumber,
    this.isLoading = false,
  });

  TableState copyWith({
    List<TableEntry>? tables,
    int? selectedTableNumber,
    bool clearSelection = false,
    bool? isLoading,
  }) {
    return TableState(
      tables: tables ?? this.tables,
      selectedTableNumber:
          clearSelection ? null : selectedTableNumber ?? this.selectedTableNumber,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Returns the UUID for the given table number, or null if not found.
  String? uuidForTable(int number) {
    try {
      return tables.firstWhere((t) => t.number == number).uuid;
    } catch (_) {
      return null;
    }
  }
}

class TableNotifier extends StateNotifier<TableState> {
  final SupabaseClient _client;
  final String? _businessId;

  TableNotifier({required SupabaseClient client, required String? businessId})
      : _client = client,
        _businessId = businessId,
        super(const TableState(tables: [], isLoading: true)) {
    if (businessId != null) _loadTables();
  }

  /// Fetch tables from Supabase and merge with local state.
  Future<void> _loadTables() async {
    if (_businessId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final rows = await _client
          .from('restaurant_tables')
          .select('id, table_number, is_occupied')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('table_number');

      final tables = (rows as List).map((row) {
        // table_number is stored as text in DB ("1", "2", etc.)
        final num = int.tryParse(row['table_number'].toString()) ?? 0;
        return TableEntry(
          number: num,
          uuid: row['id'] as String,
          status: (row['is_occupied'] as bool? ?? false)
              ? TableStatus.occupied
              : TableStatus.available,
        );
      }).toList();

      state = state.copyWith(tables: tables, isLoading: false);
    } catch (e) {
      // Fallback: generate 10 local tables (no UUIDs) so UI still renders
      state = state.copyWith(
        tables: List.generate(10, (i) => TableEntry(number: i + 1)),
        isLoading: false,
      );
    }
  }

  /// Reload tables from Supabase (call after creating/editing tables in settings)
  Future<void> refresh() => _loadTables();

  void selectTable(int number) {
    if (state.selectedTableNumber == number) {
      state = state.copyWith(clearSelection: true);
    } else {
      state = state.copyWith(selectedTableNumber: number);
    }
  }

  void occupyTable(int number, String orderId) {
    state = state.copyWith(
      tables: [
        for (final t in state.tables)
          if (t.number == number)
            t.copyWith(status: TableStatus.occupied, orderId: orderId)
          else
            t,
      ],
    );
    // Also update Supabase
    _updateOccupied(number, occupied: true);
  }

  void freeTable(int number) {
    state = state.copyWith(
      tables: [
        for (final t in state.tables)
          if (t.number == number)
            TableEntry(number: number, uuid: t.uuid)
          else
            t,
      ],
      clearSelection: state.selectedTableNumber == number,
    );
    _updateOccupied(number, occupied: false);
  }

  void clearSelection() => state = state.copyWith(clearSelection: true);

  Future<void> _updateOccupied(int number, {required bool occupied}) async {
    if (_businessId == null) return;
    try {
      await _client
          .from('restaurant_tables')
          .update({'is_occupied': occupied})
          .eq('business_id', _businessId)
          .eq('table_number', number.toString());
    } catch (_) {
      // non-fatal
    }
  }
}

final tableProvider =
    StateNotifierProvider<TableNotifier, TableState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  // Re-create (and reload) when the logged-in business changes
  final businessId = ref.watch(profileProvider).asData?.value?.businessId;
  return TableNotifier(client: client, businessId: businessId);
});

// Convenience provider
final selectedTableProvider = Provider<int?>((ref) {
  return ref.watch(tableProvider).selectedTableNumber;
});