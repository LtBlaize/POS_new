// lib/core/providers/staff_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/staff.dart';
import '../services/connectivity_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_queue_service.dart';
import '../../features/auth/auth_provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ── Staff list ────────────────────────────────────────────────────────────────

final staffListProvider =
    StateNotifierProvider<StaffListNotifier, AsyncValue<List<StaffMember>>>(
        (ref) {
  final client = ref.watch(supabaseClientProvider);
  final businessId = ref.watch(profileProvider).asData?.value?.businessId;
  final local = ref.read(localDbServiceProvider);
  final syncQueue = ref.read(syncQueueServiceProvider);

  return StaffListNotifier(
    client: client,
    businessId: businessId,
    local: local,
    syncQueue: syncQueue,
    ref: ref,
  );
});

class StaffListNotifier extends StateNotifier<AsyncValue<List<StaffMember>>> {
  final SupabaseClient _client;
  final String? _businessId;
  final LocalDbService _local;
  final SyncQueueService _syncQueue;
  final Ref _ref;

  StaffListNotifier({
    required SupabaseClient client,
    required String? businessId,
    required LocalDbService local,
    required SyncQueueService syncQueue,
    required Ref ref,
  })  : _client = client,
        _businessId = businessId,
        _local = local,
        _syncQueue = syncQueue,
        _ref = ref,
        super(const AsyncValue.loading()) {
    load();
  }

  // Read connectivity fresh at call time — never cache it
  bool get _isOnline => _ref.read(isOnlineProvider);

  Future<void> load({bool retrying = false}) async {
    if (_businessId == null) {
      state = const AsyncValue.data([]);
      return;
    }

    // Serve cache immediately so PIN lock isn't blocked
    try {
      final cached = await _local.getStaff(_businessId);
      if (cached.isNotEmpty) {
        state = AsyncValue.data(cached);
      }
    } catch (_) {}

    if (!_isOnline) return;

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

      await _local.upsertStaff(members);

      // Auto-create owner staff row for accounts registered before
      // staff_members insert was added to completeRegistration.
      // retrying guard prevents infinite recursion if RLS/replication
      // delays mean the row isn't visible immediately after insert.
      final hasOwner = members.any((m) => m.role == StaffRole.owner);
      if (!hasOwner && !retrying) {
        try {
          final profileRow = await _client
              .from('profiles')
              .select('full_name')
              .eq('business_id', _businessId)
              .eq('role', 'owner')
              .maybeSingle();

          if (profileRow != null) {
            debugPrint(
                '[Staff] No owner staff row — auto-creating for existing account...');
            await _client.from('staff_members').insert({
              'business_id': _businessId,
              'name': profileRow['full_name'] as String,
              'role': 'owner',
              'pin_hash': '',
              'is_active': true,
            });
            return load(retrying: true);
          }
        } catch (e) {
          debugPrint('[Staff] Could not auto-create owner staff row: $e');
        }
      }

      state = AsyncValue.data(members);
    } catch (e, s) {
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
      final current = state.asData?.value ?? [];
      state = AsyncValue.data(current.where((m) => m.id != id).toList());
    }
  }
}

// ── Active staff session ──────────────────────────────────────────────────────

// ── Active staff session ──────────────────────────────────────────────────────

final activeStaffProvider =
    StateNotifierProvider<ActiveStaffNotifier, StaffMember?>(
        (ref) => ActiveStaffNotifier());

class ActiveStaffNotifier extends StateNotifier<StaffMember?> {
  ActiveStaffNotifier() : super(null);

  void login(StaffMember staff) => state = staff;
  void logout() => state = null;
}

// ── Staff session conflict detection ─────────────────────────────────────────
//
// When a staff PIN is entered, we upsert a row in staff_sessions with
// this device's ID. Any other device watching the same staff_id will
// see the device_id change and lock itself.

final staffSessionServiceProvider = Provider<StaffSessionService>((ref) {
  return StaffSessionService(
    client: ref.watch(supabaseClientProvider),
  );
});

class StaffSessionService {
  final SupabaseClient _client;
  Timer? _pollTimer;

  StaffSessionService({
    required SupabaseClient client,
  })  : _client = client;
  

  /// Call this immediately after a successful PIN unlock.
  /// Upserts this device as the active session for [staff].
  /// Any other device polling will see the device_id change and lock.
  Future<void> claimSession({
    required String businessId,
    required String staffId,
  }) async {
    final deviceId = await _getDeviceId();
    try {
      await _client.from('staff_sessions').upsert(
        {
          'business_id': businessId,
          'staff_id': staffId,
          'device_id': deviceId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'staff_id', // unique index — replaces other device's row
      );
    } catch (e) {
      debugPrint('[Session] claimSession error (ignored offline): $e');
    }
  }

  /// Starts polling every 5 seconds.
  /// Calls [onKicked] if another device has claimed this staff's session.
  void startWatching({
    required String staffId,
    required VoidCallback onKicked,
  }) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkSession(staffId: staffId, onKicked: onKicked);
    });
  }

  void stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkSession({
    required String staffId,
    required VoidCallback onKicked,
  }) async {
    final deviceId = await _getDeviceId();
    try {
      final rows = await _client
          .from('staff_sessions')
          .select('device_id')
          .eq('staff_id', staffId)
          .limit(1);
      if (rows.isNotEmpty) {
        final activeDevice = rows.first['device_id'] as String?;
        if (activeDevice != null && activeDevice != deviceId) {
          onKicked();
        }
      }
    } catch (e) {
      debugPrint('[Session] poll error (ignored): $e');
    }
  }

  /// Remove this device's session row on logout/lock.
  Future<void> clearSession(String staffId) async {
    final deviceId = await _getDeviceId();
    try {
      await _client
          .from('staff_sessions')
          .delete()
          .eq('staff_id', staffId)
          .eq('device_id', deviceId);
    } catch (_) {}
  }

  static String? _cachedDeviceId;
  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
    }
    _cachedDeviceId = id;
    return id;
  }

  void dispose() => stopWatching();
}

// ── Offline PIN verification helper ──────────────────────────────────────────

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