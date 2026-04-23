import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff.dart';
import '../../features/auth/auth_provider.dart';

// ── All staff for business ────────────────────────────────────────────────────
final staffListProvider =
    StateNotifierProvider<StaffListNotifier, AsyncValue<List<StaffMember>>>(
        (ref) {
  final client = ref.watch(supabaseClientProvider);
  final businessId = ref.watch(profileProvider).asData?.value?.businessId;
  return StaffListNotifier(client: client, businessId: businessId);
});

class StaffListNotifier
    extends StateNotifier<AsyncValue<List<StaffMember>>> {
  final SupabaseClient _client;
  final String? _businessId;

  StaffListNotifier({required SupabaseClient client, required String? businessId})
      : _client = client,
        _businessId = businessId,
        super(const AsyncValue.loading()) {
    if (businessId != null) load();
  }

  Future<void> load() async {
    if (_businessId == null) return;
    state = const AsyncValue.loading();
    try {
      final rows = await _client
          .from('staff_members')
          .select()
          .eq('business_id', _businessId)
          .eq('is_active', true)
          .order('created_at');
      state = AsyncValue.data(
        (rows as List).map((r) => StaffMember.fromJson(r)).toList(),
      );
    } catch (e, s) {
      state = AsyncValue.error(e, s);
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
    await _client.from('staff_members').insert(member.toJson());
    await load();
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
    await _client.from('staff_members').update(data).eq('id', id);
    await load();
  }

  Future<void> deleteStaff(String id) async {
    await _client
        .from('staff_members')
        .update({'is_active': false}).eq('id', id);
    await load();
  }
}

// ── Currently active staff session ───────────────────────────────────────────
final activeStaffProvider =
    StateNotifierProvider<ActiveStaffNotifier, StaffMember?>((ref) {
  return ActiveStaffNotifier();
});

class ActiveStaffNotifier extends StateNotifier<StaffMember?> {
  ActiveStaffNotifier() : super(null);

  void login(StaffMember staff) => state = staff;
  void logout() => state = null;
}