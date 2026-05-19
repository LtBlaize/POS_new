// lib/features/settings/settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/business_config.dart';
import '../../features/auth/auth_provider.dart';

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

      final existingNumbers = (existing as List)
          .map((row) => int.tryParse(row['table_number'].toString()) ?? 0)
          .toSet();

      final toInsert = <int>[];
      int candidate = 1;
      while (toInsert.length < count) {
        if (!existingNumbers.contains(candidate)) {
          toInsert.add(candidate);
        }
        candidate++;
      }

      await _client.from('restaurant_tables').insert(
        toInsert.map((n) {
          final row = <String, dynamic>{
            'business_id': _businessId,
            'table_number': n.toString(),
            'is_active': true,
            'is_occupied': false,
          };
          if (roomId != null) row['room_id'] = roomId;
          return row;
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

// Convenience — discounts allowed
final discountsAllowedProvider = Provider<bool>((ref) {
  return ref.watch(businessConfigProvider)?.allowDiscounts ?? true;
});