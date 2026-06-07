// lib/core/providers/app_context_provider.dart
//
// Single source of truth for the active business ID.
// Every provider that needs businessId reads this — never profileProvider
// directly — so multi-business switching later is a one-line change here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/auth_provider.dart';

final activeBusinessIdProvider = Provider<String?>((ref) {
  // Watch the future — returns null while loading, then re-notifies all
  // dependents once the profile resolves. Using .asData?.value here would
  // permanently return null if any dependent reads before the future settles.
  final profile = ref.watch(profileProvider);
  return profile.when(
    data: (p) => p?.businessId,
    loading: () => null,
    error: (_, _) => null,
  );
}); 