// lib/core/providers/admin_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/auth_provider.dart';

final isPlatformAdminProvider = FutureProvider<bool>((ref) async {
  final authState = ref.watch(authStateProvider);
  var user = authState.value;

  // Same fallback as profileProvider: authStateProvider (a stream) doesn't
  // reliably have emitted by the time this runs on cold boot / session
  // restore, even though a session already exists. Give it a short window,
  // then fall back to reading the session directly instead of resolving
  // false prematurely.
  if (user == null) {
    try {
      user = await ref.watch(authStateProvider.stream).first.timeout(const Duration(seconds: 2));
    } catch (_) {
      user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        debugPrint('[AdminCheck] authState timeout — falling back to currentUser');
      }
    }
  }

  if (user == null) return false;

  try {
    final result = await Supabase.instance.client.rpc('is_platform_admin');
    return result as bool? ?? false;
  } catch (e) {
    debugPrint('[AdminCheck] RPC failed: $e');
    return false;
  }
});