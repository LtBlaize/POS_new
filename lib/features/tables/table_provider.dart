import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/auth_provider.dart';

enum TableStatus { available, occupied, reserved }

class TableEntry {
  final String name;
  final String? uuid;
  final TableStatus status;
  final String? orderId;
  final double x;
  final double y;
  final double w;
  final double h;

  const TableEntry({
    required this.name,
    this.uuid,
    this.status = TableStatus.available,
    this.orderId,
    this.x = 0,
    this.y = 0,
    this.w = 80,
    this.h = 80,
  });

  TableEntry copyWith({
    String? uuid,
    TableStatus? status,
    String? orderId,
    bool clearOrder = false,
    double? x,
    double? y,
    double? w,
    double? h,
  }) {
    return TableEntry(
      name: name,
      uuid: uuid ?? this.uuid,
      status: status ?? this.status,
      orderId: clearOrder ? null : (orderId ?? this.orderId),
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
    );
  }
}

class TableState {
  final List<TableEntry> tables;
  final String? selectedTableName;
  final bool isLoading;

  const TableState({
    required this.tables,
    this.selectedTableName,
    this.isLoading = false,
  });

  TableState copyWith({
    List<TableEntry>? tables,
    String? selectedTableName,
    bool clearSelection = false,
    bool? isLoading,
  }) {
    return TableState(
      tables: tables ?? this.tables,
      selectedTableName:
          clearSelection ? null : selectedTableName ?? this.selectedTableName,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  String? uuidForTable(String name) {
    try {
      return tables.firstWhere((t) => t.name == name).uuid;
    } catch (_) {
      return null;
    }
  }

  String? tableNameForUuid(String uuid) {
    try {
      return tables.firstWhere((t) => t.uuid == uuid).name;
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

  Future<void> _loadTables() async {
    if (_businessId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final rows = await _client
          .from('restaurant_tables')
          .select('id, table_number, is_occupied, metadata')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('table_number');

      final tables = (rows as List).map((row) {
        final meta = row['metadata'] as Map<String, dynamic>? ?? {};
        return TableEntry(
          name: row['table_number'].toString(),
          uuid: row['id'] as String,
          status: (row['is_occupied'] as bool? ?? false)
              ? TableStatus.occupied
              : TableStatus.available,
          x: (meta['x'] as num?)?.toDouble() ?? 0,
          y: (meta['y'] as num?)?.toDouble() ?? 0,
          w: (meta['w'] as num?)?.toDouble() ?? 80,
          h: (meta['h'] as num?)?.toDouble() ?? 80,
        );
      }).toList();

      state = state.copyWith(tables: tables, isLoading: false);
    } catch (e) {
      state = state.copyWith(tables: [], isLoading: false);
    }
  }

  Future<void> refresh() => _loadTables();

  void selectTable(String name) {
    if (state.selectedTableName == name) {
      state = state.copyWith(clearSelection: true);
    } else {
      state = state.copyWith(selectedTableName: name);
    }
  }

  void clearSelection() => state = state.copyWith(clearSelection: true);

  void occupyTable(String name, String orderId) {
    state = state.copyWith(
      tables: [
        for (final t in state.tables)
          if (t.name == name)
            t.copyWith(status: TableStatus.occupied, orderId: orderId)
          else
            t,
      ],
    );
    _updateOccupied(name, occupied: true);
  }

  void freeTable(String name) {
    state = state.copyWith(
      tables: [
        for (final t in state.tables)
          if (t.name == name)
            TableEntry(name: name, uuid: t.uuid)
          else
            t,
      ],
      clearSelection: state.selectedTableName == name,
    );
    _updateOccupied(name, occupied: false);
  }

  void moveTable(String name, double x, double y) {
    state = state.copyWith(
      tables: [
        for (final t in state.tables)
          if (t.name == name) t.copyWith(x: x, y: y) else t,
      ],
    );
  }

  Future<void> saveLayout() async {
    if (_businessId == null) return;
    for (final t in state.tables) {
      if (t.uuid == null) continue;
      try {
        await _client
            .from('restaurant_tables')
            .update({'metadata': {'x': t.x, 'y': t.y, 'w': t.w, 'h': t.h}})
            .eq('id', t.uuid!);
      } catch (_) {}
    }
  }

  Future<void> _updateOccupied(String name, {required bool occupied}) async {
    if (_businessId == null) return;
    try {
      await _client
          .from('restaurant_tables')
          .update({'is_occupied': occupied})
          .eq('business_id', _businessId)
          .eq('table_number', name);
    } catch (_) {}
  }
}

final tableProvider =
    StateNotifierProvider<TableNotifier, TableState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final businessId = ref.watch(profileProvider).asData?.value?.businessId;
  return TableNotifier(client: client, businessId: businessId);
});

final selectedTableProvider = Provider<String?>((ref) {
  return ref.watch(tableProvider).selectedTableName;
});