// lib/core/providers/app_context_provider.dart
//
// Single source of truth for the active business ID.
// Every provider that needs businessId reads this — never profileProvider
// directly — so multi-business switching later is a one-line change here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/auth_provider.dart';

final activeBusinessIdProvider = Provider<String?>((ref) {
  // .value keeps the previous profile while a refresh is in flight.
  return ref.watch(profileProvider).value?.businessId;
});