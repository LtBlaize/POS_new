// lib/core/providers/staff_provider.dart
//
// Cache-first staff list:
//   Online  → fetch from Supabase, write-through to SQLite
//   Offline → read from SQLite; mutations queued for later sync
//
// PIN verification always works offline (hashes stored locally).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/staff.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';

// ── Staff list ────────────────────────────────────────────────────────────────

final staffListProvider =
    StateNotifierProvider<StaffListNotifier, AsyncValue<List<StaffMember>>>(
        (ref) {
  final client = ref.watch(supabaseClientProvider);
  final businessId = ref.watch(profileProvider).asData?.value?.businessId;
  final local = ref.read(localDbServiceProvider);
  final syncQueue = ref.read(syncQueueServiceProvider);
  final isOnline = ref.read(isOnlineProvider);

  return StaffListNotifier(
    client: client,
    businessId: businessId,
    local: local,
    syncQueue: syncQueue,
    isOnline: isOnline,
  );
});

class StaffListNotifier
    extends StateNotifier<AsyncValue<List<StaffMember>>> {
  final SupabaseClient _client;
  final String? _businessId;
  final LocalDbService _local;
  final SyncQueueService _syncQueue;
  final bool _isOnline;

  StaffListNotifier({
    required SupabaseClient client,
    required String? businessId,
    required LocalDbService local,
    required SyncQueueService syncQueue,
    required bool isOnline,
  })  : _client = client,
        _businessId = businessId,
        _local = local,
        _syncQueue = syncQueue,
        _isOnline = isOnline,
        super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    if (_businessId == null) {
      state = const AsyncValue.data([]);
      return;
    }

    // Always try local cache first for instant display
    try {
      final cached = await _local.getStaff(_businessId);
      if (cached.isNotEmpty) {
        state = AsyncValue.data(cached);
      }
    } catch (_) {}

    if (!_isOnline) return; // Stick with cache offline

    state = const AsyncValue.loading();
    try {
      final rows = await _client
          .from('staff_members')
          .select()
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('created_at');

      final members =
          (rows as List).map((r) => StaffMember.fromJson(r)).toList();

      // Write-through to local cache
      await _local.upsertStaff(members);

      state = AsyncValue.data(members);
    } catch (e, s) {
      // Fall back to cache on network error
      try {
        final cached = await _local.getStaff(_businessId);
        state = AsyncValue.data(cached);
      } catch (_) {
        state = AsyncValue.error(e, s);
      }
    }
  }

  Future<void> addStaff({
    required String name,
    required StaffRole role,
    required String pin,
  }) async {
    if (_businessId == null) return;

    final member = StaffMember(
      id: '',
      businessId: _businessId,
      name: name,
      role: role,
      pinHash: StaffMember.hashPin(pin),
      isActive: true,
    );

    if (_isOnline) {
      await _client.from('staff_members').insert(member.toJson());
      await load();
    } else {
      await _syncQueue.enqueue(
        operation: 'add_staff',
        tableName: 'staff_members',
        recordId: 'new_${DateTime.now().millisecondsSinceEpoch}',
        payload: member.toJson(),
      );
      // Optimistically add to local cache
      final current = state.asData?.value ?? [];
      state = AsyncValue.data([
        ...current,
        StaffMember(
          id: 'offline_${DateTime.now().millisecondsSinceEpoch}',
          businessId: _businessId,
          name: name,
          role: role,
          pinHash: StaffMember.hashPin(pin),
          isActive: true,
        ),
      ]);
    }
  }

  Future<void> updateStaff({
    required String id,
    required String name,
    required StaffRole role,
    String? newPin,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'role': role.value,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (newPin != null && newPin.isNotEmpty) {
      data['pin_hash'] = StaffMember.hashPin(newPin);
    }

    if (_isOnline) {
      await _client.from('staff_members').update(data).eq('id', id);
      await load();
    } else {
      await _syncQueue.enqueue(
        operation: 'update_staff',
        tableName: 'staff_members',
        recordId: id,
        payload: data,
      );
    }
  }

  Future<void> deleteStaff(String id) async {
    if (_isOnline) {
      await _client
          .from('staff_members')
          .update({'is_active': false}).eq('id', id);
      await load();
    } else {
      await _syncQueue.enqueue(
        operation: 'delete_staff',
        tableName: 'staff_members',
        recordId: id,
        payload: {'is_active': false},
      );
      // Optimistically remove from list
      final current = state.asData?.value ?? [];
      state = AsyncValue.data(current.where((m) => m.id != id).toList());
    }
  }
}

// ── Active staff session ──────────────────────────────────────────────────────

final activeStaffProvider =
    StateNotifierProvider<ActiveStaffNotifier, StaffMember?>((ref) {
  return ActiveStaffNotifier();
});

class ActiveStaffNotifier extends StateNotifier<StaffMember?> {
  ActiveStaffNotifier() : super(null);

  void login(StaffMember staff) => state = staff;
  void logout() => state = null;
}

// ── Offline PIN verification helper ──────────────────────────────────────────

/// Verify a staff PIN against the local cache — works 100% offline.
/// Returns the matching StaffMember or null.
Future<StaffMember?> verifyPinOffline({
  required String businessId,
  required String pin,
  required LocalDbService local,
}) async {
  final staff = await local.getStaff(businessId);
  try {
    return staff.firstWhere((m) => m.checkPin(pin));
  } catch (_) {
    return null;
  }
}