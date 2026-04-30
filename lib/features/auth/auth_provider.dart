// lib/features/auth/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/profile.dart';
import '../../core/models/business.dart';
import '../../config/business_config.dart' show BusinessFeatures;
import '../../core/services/feature_manager.dart';
import '../../features/settings/settings_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

final authStateProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange.map((event) => event.session?.user);
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  final userAsync = ref.watch(authStateProvider);
  final user = userAsync.asData?.value;
  if (user == null) return null;

  final client = ref.watch(supabaseClientProvider);
  final map = await client
      .from('profiles')
      .select('*, businesses(*)')
      .eq('id', user.id)
      .maybeSingle();

  return map != null ? Profile.fromMap(map) : null;
});

final businessTypeProvider = Provider<BusinessType?>((ref) {
  return ref.watch(profileProvider).asData?.value?.businessType;
});

final businessProvider = Provider<Business?>((ref) {
  return ref.watch(profileProvider).asData?.value?.business;
});

final featureManagerProvider = Provider<FeatureManager?>((ref) {
  final businessType = ref.watch(businessTypeProvider);
  if (businessType == null) return null;

  // retail keeps all its features as-is
  // restaurant base is just 'inventory' — kitchen/tables depend on config toggles
  final base = businessType.isRestaurant
      ? ['inventory']
      : BusinessFeatures.retail;

  final features = List<String>.from(base);

  if (businessType.isRestaurant) {
    final config = ref.watch(businessConfigProvider);
    if (config != null) {
      if (config.enableKitchenDisplay) features.add('kitchen');
      if (config.enableTableManagement) features.add('tables');
    }
  }

  return FeatureManager(features);
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

// ── AuthService class ─────────────────────────────────────────────────────────

class AuthService {
  final SupabaseClient _client;
  AuthService(this._client);

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<String> startRegistration({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    final userId = response.user?.id;
    if (userId == null) throw Exception('Registration failed.');

    if (_client.auth.currentSession == null) {
      debugPrint('No session after signUp — signing in manually...');
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    }

    int attempts = 0;
    while (_client.auth.currentSession == null && attempts < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (_client.auth.currentSession == null) {
      throw Exception('Could not establish session. Please try again.');
    }

    debugPrint('Session confirmed: ${_client.auth.currentSession!.user.id}');
    return userId;
  }

  Future<void> completeRegistration({
    required String userId,
    required String fullName,
    required String businessName,
    required String businessType,
  }) async {
    try {
      debugPrint('=== completeRegistration START ===');

      if (_client.auth.currentSession == null) {
        debugPrint('No session at completeRegistration — waiting...');
        int attempts = 0;
        while (_client.auth.currentSession == null && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 200));
          attempts++;
        }
        if (_client.auth.currentSession == null) {
          throw Exception('No active session. Please try again.');
        }
      }

      debugPrint(
        'Access token prefix: '
        '${_client.auth.currentSession!.accessToken.substring(0, 20)}',
      );

      // 1. Business
      debugPrint('Inserting business...');
      final business = await _client
          .from('businesses')
          .insert({
            'name': businessName,
            'business_type': businessType,
          })
          .select()
          .single();

      final businessId = business['id'] as String;
      debugPrint('Business inserted: $businessId');

      // 2. Profile
      debugPrint('Inserting profile...');
      await _client.from('profiles').insert({
        'id': userId,
        'business_id': businessId,
        'full_name': fullName,
        'role': 'owner',
      });
      debugPrint('Profile inserted.');

      // 3. Owner as staff member
      debugPrint('Inserting owner as staff member...');
      await _client.from('staff_members').insert({
        'business_id': businessId,
        'name': fullName,
        'role': 'owner',
        'pin_hash': '',
        'is_active': true,
      });
      debugPrint('Owner staff member inserted.');

      // 4. Business config with correct role_permissions per business type
      debugPrint('Inserting business_config...');

      // Restaurant: manager + cashier + kitchen roles, no credits
      // Retail: cashier only, with utang/credits
      final rolePermissions = businessType == 'restaurant'
          ? {
              'manager': ['pos', 'orders', 'kitchen', 'inventory', 'reports', 'settings'],
              'cashier': ['pos', 'orders', 'settings'],
              'kitchen': ['kitchen'],
            }
          : {
              'cashier': ['pos', 'orders', 'utang'],
            };

      await _client.from('business_configs').insert({
        'business_id': businessId,
        'tax_rate': 0.00,
        'enable_kitchen_display': businessType == 'restaurant',
        'enable_table_management': businessType == 'restaurant',
        'enable_barcode_scanner': businessType == 'retail',
        'enable_inventory_alerts': businessType == 'retail',
        // ✅ Correct permissions per business type from day one
        'role_permissions': rolePermissions,
      });
      debugPrint('=== completeRegistration DONE ===');
    } catch (e, stack) {
      debugPrint('=== completeRegistration FAILED ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;
}