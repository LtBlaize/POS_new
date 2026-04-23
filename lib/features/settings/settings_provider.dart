import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_provider.dart';

// ── BusinessConfig model ──────────────────────────────────────────────────────
class BusinessConfig {
  final String id;
  final double taxRate;
  final String? receiptFooter;
  final bool allowDiscounts;
  final bool requireTableOnOrder;
  final bool enableKitchenDisplay;
  final bool enableTableManagement;
  final int numTables;
  final bool enableBarcodeScanner;
  final bool enableInventoryAlerts;
  final int lowStockThreshold;

  const BusinessConfig({
    required this.id,
    this.taxRate = 0.0,
    this.receiptFooter,
    this.allowDiscounts = true,
    this.requireTableOnOrder = false,
    this.enableKitchenDisplay = false,
    this.enableTableManagement = false,
    this.numTables = 0,
    this.enableBarcodeScanner = false,
    this.enableInventoryAlerts = false,
    this.lowStockThreshold = 5,
  });

  factory BusinessConfig.fromMap(Map<String, dynamic> m) => BusinessConfig(
        id: m['id'] as String,
        taxRate: (m['tax_rate'] as num?)?.toDouble() ?? 0.0,
        receiptFooter: m['receipt_footer'] as String?,
        allowDiscounts: m['allow_discounts'] as bool? ?? true,
        requireTableOnOrder: m['require_table_on_order'] as bool? ?? false,
        enableKitchenDisplay: m['enable_kitchen_display'] as bool? ?? false,
        enableTableManagement:
            m['enable_table_management'] as bool? ?? false,
        numTables: m['num_tables'] as int? ?? 0,
        enableBarcodeScanner: m['enable_barcode_scanner'] as bool? ?? false,
        enableInventoryAlerts:
            m['enable_inventory_alerts'] as bool? ?? false,
        lowStockThreshold: m['low_stock_threshold'] as int? ?? 5,
      );

  Map<String, dynamic> toMap() => {
        'tax_rate': taxRate,
        'receipt_footer': receiptFooter,
        'allow_discounts': allowDiscounts,
        'require_table_on_order': requireTableOnOrder,
        'enable_kitchen_display': enableKitchenDisplay,
        'enable_table_management': enableTableManagement,
        'num_tables': numTables,
        'enable_barcode_scanner': enableBarcodeScanner,
        'enable_inventory_alerts': enableInventoryAlerts,
        'low_stock_threshold': lowStockThreshold,
      };

  BusinessConfig copyWith({
    double? taxRate,
    String? receiptFooter,
    bool? allowDiscounts,
    bool? requireTableOnOrder,
    bool? enableKitchenDisplay,
    bool? enableTableManagement,
    int? numTables,
    bool? enableBarcodeScanner,
    bool? enableInventoryAlerts,
    int? lowStockThreshold,
  }) =>
      BusinessConfig(
        id: id,
        taxRate: taxRate ?? this.taxRate,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        allowDiscounts: allowDiscounts ?? this.allowDiscounts,
        requireTableOnOrder: requireTableOnOrder ?? this.requireTableOnOrder,
        enableKitchenDisplay:
            enableKitchenDisplay ?? this.enableKitchenDisplay,
        enableTableManagement:
            enableTableManagement ?? this.enableTableManagement,
        numTables: numTables ?? this.numTables,
        enableBarcodeScanner:
            enableBarcodeScanner ?? this.enableBarcodeScanner,
        enableInventoryAlerts:
            enableInventoryAlerts ?? this.enableInventoryAlerts,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      );
}

// ── Room model ────────────────────────────────────────────────────────────────
class RoomEntry {
  final String id;
  final String name;
  final int sortOrder;

  const RoomEntry({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory RoomEntry.fromMap(Map<String, dynamic> m) => RoomEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        sortOrder: m['sort_order'] as int? ?? 0,
      );
}

// ── Settings state ────────────────────────────────────────────────────────────
class SettingsState {
  final BusinessConfig? config;
  final List<RoomEntry> rooms;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const SettingsState({
    this.config,
    this.rooms = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  SettingsState copyWith({
    BusinessConfig? config,
    List<RoomEntry>? rooms,
    bool? isLoading,
    bool? isSaving,
    String? error,
  }) =>
      SettingsState(
        config: config ?? this.config,
        rooms: rooms ?? this.rooms,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: error,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class SettingsNotifier extends StateNotifier<SettingsState> {
  final SupabaseClient _client;
  final String? _businessId;

  SettingsNotifier({
    required SupabaseClient client,
    required String? businessId,
  })  : _client = client,
        _businessId = businessId,
        super(const SettingsState(isLoading: true)) {
    if (businessId != null) _load();
  }

  Future<void> _load() async {
    if (_businessId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      // Load config and rooms in parallel
      final results = await Future.wait([
        _client
            .from('business_configs')
            .select()
            .eq('business_id', _businessId)
            .maybeSingle(),
        _client
            .from('restaurant_rooms')
            .select('id, name, sort_order')
            .eq('business_id', _businessId)
            .order('sort_order'),
      ]);

      final configMap = results[0] as Map<String, dynamic>?;
      final roomRows = results[1] as List;

      state = state.copyWith(
        config: configMap != null ? BusinessConfig.fromMap(configMap) : null,
        rooms: roomRows.map((r) => RoomEntry.fromMap(r)).toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Config save ─────────────────────────────────────────────────────────────
  Future<void> saveConfig(BusinessConfig config) async {
    if (_businessId == null) return;
    state = state.copyWith(isSaving: true);
    try {
      await _client
          .from('business_configs')
          .update(config.toMap())
          .eq('business_id', _businessId);
      state = state.copyWith(config: config, isSaving: false);
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
    }
  }

  // ── Table CRUD ──────────────────────────────────────────────────────────────
  Future<void> addTables(int count, String? roomId) async {
  if (_businessId == null) return;
  try {
    final existing = await _client
        .from('restaurant_tables')
        .select('table_number')
        .eq('business_id', _businessId)
        .eq('is_active', true);

    // Collect ALL existing numbers (active ones)
    final existingNumbers = (existing as List)
        .map((row) => int.tryParse(row['table_number'].toString()) ?? 0)
        .toSet();

    // Find next N numbers not already taken
    final toInsert = <int>[];
    int candidate = 1;
    while (toInsert.length < count) {
      if (!existingNumbers.contains(candidate)) {
        toInsert.add(candidate);
      }
      candidate++;
    }

    await _client.from('restaurant_tables').insert(
      toInsert.map((n) => {
        'business_id': _businessId,
        'table_number': n.toString(),
        'is_active': true,
        'is_occupied': false,
        if (roomId != null) 'room_id': roomId,
      }).toList(),
    );
  } catch (e) {
    state = state.copyWith(error: e.toString());
  }
}

  Future<void> deleteTable(String tableUuid) async {
    try {
      await _client
          .from('restaurant_tables')
          .update({'is_active': false})
          .eq('id', tableUuid);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // ── Room CRUD ───────────────────────────────────────────────────────────────
  Future<void> addRoom(String name) async {
    if (_businessId == null) return;
    try {
      await _client.from('restaurant_rooms').insert({
        'business_id': _businessId,
        'name': name,
        'sort_order': state.rooms.length,
      });
      await _load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteRoom(String roomId) async {
    try {
      await _client
          .from('restaurant_tables')
          .update({'room_id': null}).eq('room_id', roomId);
      await _client.from('restaurant_rooms').delete().eq('id', roomId);
      await _load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> refresh() => _load();
}

// ── Providers ─────────────────────────────────────────────────────────────────
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final businessId = ref.watch(profileProvider).asData?.value?.businessId;
  return SettingsNotifier(client: client, businessId: businessId);
});

// Convenience — just the config
final businessConfigProvider = Provider<BusinessConfig?>((ref) {
  return ref.watch(settingsProvider).config;
});