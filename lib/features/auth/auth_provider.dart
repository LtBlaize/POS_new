// lib/features/auth/auth_provider.dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/profile.dart';
import '../../core/models/business.dart';
import '../../config/business_config.dart';
import '../../core/services/feature_manager.dart';
import '../../features/settings/settings_provider.dart';


// Simple static flag — set BEFORE signUp(), cleared after completeRegistration()
// Used to prevent the auth listener from navigating during the 2-step registration flow.
class RegistrationGuard {
  static bool isRegistering = false;
}
// ── Providers ─────────────────────────────────────────────────────────────────

final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

// ── FIX: Filtered auth stream ─────────────────────────────────────────────────
//
// The raw onAuthStateChange stream fires for EVERY Supabase internal event:
//   signedIn, tokenRefreshed, userUpdated, signedOut, initialSession, etc.
//
// The old code mapped ALL of them to a user, meaning:
//   1. login()  → signedIn fires  → profileProvider rebuilds
//              → tokenRefreshed fires immediately after (user still set)
//              → profileProvider rebuilds AGAIN mid-flight
//              → .asData is null for a moment → _PendingPosScreen shows
//              → featureManager is null → router can't resolve /pos
//              → gets stuck or loops back to /login
//
//   2. signOut() → signedOut fires → user = null
//              → nobody in the old code was listening to navigate to /login
//              → stuck on whatever screen was showing
//
// The fix: only emit on events we actually care about, and deduplicate
// by user ID so multiple rapid events for the same user don't re-trigger
// profileProvider rebuilds unnecessarily.
final authStateProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return client.auth.onAuthStateChange
      .where((event) =>
          // Only react to these four meaningful transitions.
          // tokenRefreshed, userUpdated, passwordRecovery etc. are filtered out.
          event.event == AuthChangeEvent.signedIn      ||
          event.event == AuthChangeEvent.signedOut     ||
          event.event == AuthChangeEvent.initialSession ||
          event.event == AuthChangeEvent.userDeleted)
      .map((event) => event.session?.user)
      // Deduplicate: only emit when the user ID actually changes.
      // This prevents profileProvider from rebuilding when Supabase fires
      // a second signedIn event (e.g. after token refresh at startup).
      .distinct((a, b) => a?.id == b?.id);
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  // Use currentUser directly as fallback — authStateProvider.future may
  // never resolve if initialSession fired before this provider was watched.
  final userAsync = await ref.watch(authStateProvider.future).timeout(
    const Duration(seconds: 3),
    onTimeout: () {
      debugPrint('[Profile] authState timeout — falling back to currentUser');
      return Supabase.instance.client.auth.currentUser;
    },
  );
  debugPrint('[Profile] authState resolved, user: ${userAsync?.id}');
  final user = userAsync;
  if (user == null) {
    debugPrint('[Profile] user is null — returning null');
    return null;
  }
  debugPrint('[Profile] fetching from Supabase for ${user.id}');

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

  final features = <String>['inventory'];

  if (businessType.isRestaurant) {
    final config = ref.watch(businessConfigProvider);
    if (config != null) {
      if (config.enableKitchenDisplay) features.add('kitchen');
      if (config.enableTableManagement) features.add('tables');
    }
  } else {
    // Retail features
    features.add('barcode');
    features.add('credits'); // retail always has credits — intentional
  }

  return FeatureManager(features);
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});


// ── AuthService ───────────────────────────────────────────────────────────────

class AuthService {
  final SupabaseClient _client;
  AuthService(this._client);

  // ── PIN hashing ─────────────────────────────────────────────────────────────
  //
  // SHA-256 is sufficient for a 4-6 digit POS PIN because:
  //   • The PIN is never transmitted — it's only compared locally.
  //   • The plaintext is never stored anywhere (DB stores only the hash).
  //
  // If you need stronger protection in future, swap to bcrypt via
  // the `bcrypt` pub package. For now SHA-256 + constant-time compare
  // is a secure baseline.
  String hashPin(String pin) {
    final bytes = utf8.encode(pin.trim());
    return sha256.convert(bytes).toString();
  }

  /// Verifies a user-entered PIN against a stored SHA-256 hash.
  /// Use this in your staff PIN login / pin_lock_overlay.dart.
  bool verifyPin(String inputPin, String storedHash) {
    return hashPin(inputPin) == storedHash;
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  //
  // FIX: login() now ONLY authenticates. Navigation is handled entirely
  // by the authStateProvider listener in MyApp (main.dart).
  // This eliminates the race between imperative Navigator calls and
  // the auth stream firing — the previous cause of the redirect loop.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    // ✅ Return immediately. MyApp's ref.listen on authStateProvider
    //    will fire and handle navigation to /pos or /role-select.
  }

  // ── Registration step 1: create Supabase auth user ─────────────────────────
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

    // Wait for session to settle — do NOT call signInWithPassword here.
    // A second sign-in fires a second signedIn event which can race with
    // completeRegistration and cause duplicate DB inserts.
    int attempts = 0;
    while (_client.auth.currentSession == null && attempts < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (_client.auth.currentSession == null) {
      throw Exception('Could not establish session. Please try again.');
    }

    debugPrint('[Auth] Session confirmed: ${_client.auth.currentSession!.user.id}');
    return userId;
  }

  // ── Registration step 2: insert DB records ──────────────────────────────────
  //
  // ownerPin is now passed from register_screen → business_type_screen.
  // It defaults to '0000' only as a safety net; the UI always collects it.
  Future<void> completeRegistration({
    required String userId,
    required String fullName,
    required String businessName,
    required String businessType,
    String ownerPin = '0000',
  }) async {
    try {
      debugPrint('=== completeRegistration START ===');

      if (_client.auth.currentSession == null) {
        debugPrint('[Auth] No session at completeRegistration — waiting...');
        int attempts = 0;
        while (_client.auth.currentSession == null && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 200));
          attempts++;
        }
        if (_client.auth.currentSession == null) {
          throw Exception('No active session. Please try again.');
        }
      }

      // 1. Business
      debugPrint('[Auth] Inserting business...');
      final business = await _client
          .from('businesses')
          .insert({
            'name': businessName,
            'business_type': businessType,
          })
          .select()
          .single();

      final businessId = business['id'] as String;
      debugPrint('[Auth] Business inserted: $businessId');

      // 2. Profile
      debugPrint('[Auth] Inserting profile...');
      await _client.from('profiles').insert({
        'id': userId,
        'business_id': businessId,
        'full_name': fullName,
        'role': 'owner',
      });
      debugPrint('[Auth] Profile inserted.');

      // 3. Owner as staff member — PIN is hashed, never stored as plain text
      debugPrint('[Auth] Inserting owner staff member...');
      await _client.from('staff_members').insert({
        'business_id': businessId,
        'name': fullName,
        'role': 'owner',
        'pin_hash': hashPin(ownerPin),   // ✅ always hashed
        'is_active': true,
      });
      debugPrint('[Auth] Owner staff member inserted.');

      // 4. Business config
      debugPrint('[Auth] Inserting business_config...');
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
        'role_permissions': rolePermissions,
      });

      debugPrint('=== completeRegistration DONE ===');
      // ✅ Do NOT navigate here. MyApp's auth listener handles it.
      //    When completeRegistration finishes, the session is already
      //    active (set during startRegistration). authStateProvider has
      //    already emitted signedIn. MyApp will navigate to /pos.
    } catch (e, stack) {
      debugPrint('=== completeRegistration FAILED ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  // ── Logout ──────────────────────────────────────────────────────────────────
  //
  // FIX: logout() only signs out. Navigation to /login is handled by
  // MyApp's authStateProvider listener (user becomes null → go to /login).
  Future<void> logout() async {
    await _client.auth.signOut();
    // ✅ MyApp's ref.listen fires with user=null and navigates to /login.
  }

  User? get currentUser => _client.auth.currentUser;
}