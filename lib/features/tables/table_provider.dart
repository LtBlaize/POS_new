import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/auth_provider.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/order.dart';
import '../../core/services/local_db_service.dart';

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
  Future<void> deleteTable(String uuid) async {
    try {
      await _client
          .from('restaurant_tables')
          .update({'is_active': false})
          .eq('id', uuid);
      await _loadTables();
    } catch (_) {}
  }

    List<TableEntry> _parseRows(List rows) => rows.map((r) {
        final row = Map<String, dynamic>.from(r as Map);
        final meta = (row['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
        final openOrder = (row['orders'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((o) =>
                o['paid_at'] == null &&
                o['status'] != 'completed' &&
                o['status'] != 'cancelled')
            .firstOrNull;
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
          orderId: openOrder?['id'] as String?,
        );
      }).toList();

  Future<void> _loadTables() async {
    if (_businessId == null) return;
    final local = LocalDbService();
    final key = 'tables:$_businessId';
    state = state.copyWith(isLoading: true);
    try {
      final rows = await _client
          .from('restaurant_tables')
          .select(
              'id, table_number, is_occupied, metadata, orders!orders_table_id_fkey(id, status, paid_at)')
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('table_number')
          .timeout(const Duration(seconds: 6));
      await local.setKv(key, rows);
      state = state.copyWith(tables: _parseRows(rows as List), isLoading: false);
    } catch (e) {
      debugPrint('[Tables] load failed, using cache: $e');
      final cached = await local.getKv(key);
      var tables = cached is List ? _parseRows(cached) : <TableEntry>[];
      tables = await _overlayLocalOccupancy(tables, local);
      state = state.copyWith(tables: tables, isLoading: false);
    }
  }

  /// Offline: work out which tables are occupied from local unpaid orders.
  Future<List<TableEntry>> _overlayLocalOccupancy(
      List<TableEntry> tables, LocalDbService local) async {
    try {
      final orders = await local.getOrders(_businessId!);
      final byId = {for (final o in orders) o.id: o};
      final open = <String, Order>{};
      for (final o in orders) {
        if (o.tableId == null || o.paidAt != null) continue;
        if (o.status == OrderStatus.cancelled ||
            o.status == OrderStatus.completed) continue;
        open.putIfAbsent(o.tableId!, () => o); // newest first
      }
      return [
        for (final t in tables)
          if (t.uuid != null && open.containsKey(t.uuid))
            t.copyWith(
                status: TableStatus.occupied, orderId: open[t.uuid]!.id)
          else if (t.orderId != null && byId[t.orderId] != null)
            t.copyWith(status: TableStatus.available, clearOrder: true)
          else
            t,
      ];
    } catch (_) {
      return tables;
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
            t.copyWith(
              status: TableStatus.available,
              clearOrder: true,
            )
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
  final businessId = ref.watch(
      profileProvider.select((p) => p.value?.businessId));
  return TableNotifier(client: client, businessId: businessId);
});

final selectedTableProvider = Provider<String?>((ref) {
  return ref.watch(tableProvider).selectedTableName;
});
