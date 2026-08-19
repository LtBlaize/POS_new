// lib/features/admin/settings/admin_settings_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUserRow {
  final String id;
  final String authUserId;
  final String email;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  AdminUserRow({
    required this.id,
    required this.authUserId,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminUserRow.fromMap(Map<String, dynamic> map) => AdminUserRow(
        id: map['id'] as String,
        authUserId: map['auth_user_id'] as String,
        email: map['email'] as String? ?? '(no email)',
        role: map['role'] as String,
        isActive: map['is_active'] as bool,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// list_admin_users() is security-definer and checks platform_admin itself
/// (see phase12 migration) — it throws for non-platform_admin admins, which
/// the screen surfaces as an access-restricted state, not a generic error.
final adminUsersListProvider = FutureProvider.autoDispose<List<AdminUserRow>>((ref) async {
  final rows = await Supabase.instance.client.rpc('list_admin_users');
  return (rows as List).map((r) => AdminUserRow.fromMap(r as Map<String, dynamic>)).toList();
});

/// The signed-in admin's own admin_users.id — used to disable the
/// deactivate action on your own row client-side. The server enforces this
/// independently (admin_manage_admin_user raises on self-deactivate), so
/// this is purely to avoid a round trip for an outcome you could predict.
final currentAdminIdProvider = Provider.autoDispose<String?>((ref) {
  final rows = ref.watch(adminUsersListProvider).value;
  final authUserId = Supabase.instance.client.auth.currentUser?.id;
  if (rows == null || authUserId == null) return null;
  for (final r in rows) {
    if (r.authUserId == authUserId) return r.id;
  }
  return null;
});

class AdminSettingsService {
  final _client = Supabase.instance.client;

  Future<void> deactivate(String targetAdminId, {String? reason}) =>
      _call('deactivate', targetAdminId, reason: reason);
  Future<void> reactivate(String targetAdminId, {String? reason}) =>
      _call('reactivate', targetAdminId, reason: reason);
  Future<void> setRole(String targetAdminId, String role, {String? reason}) =>
      _call('set_role', targetAdminId, role: role, reason: reason);

  /// Stubbed server-side (see admin-manage-admins Edge Function) — always
  /// throws with a user-facing message right now.
  Future<void> invite(String email) async {
    final res = await _client.functions.invoke(
      'admin-manage-admins',
      body: {'action': 'invite', 'email': email},
    );
    final error = (res.data is Map) ? res.data['error'] as String? : null;
    throw Exception(error ?? "Inviting new admins isn't available yet.");
  }

  Future<void> _call(String action, String targetAdminId, {String? role, String? reason}) async {
    final res = await _client.functions.invoke(
      'admin-manage-admins',
      body: {
        'action': action,
        'target_admin_id': targetAdminId,
        if (role != null) 'role': role,
        if (reason != null) 'reason': reason,
      },
    );
    if (res.status != 200) {
      final error = (res.data is Map) ? res.data['error'] as String? : null;
      throw Exception(error ?? 'Request failed ($action)');
    }
  }
}

final adminSettingsServiceProvider = Provider<AdminSettingsService>((ref) => AdminSettingsService());