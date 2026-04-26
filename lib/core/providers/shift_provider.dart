// lib/core/providers/shift_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift.dart';
import '../services/shift_service.dart';
import '../providers/staff_provider.dart';          // ← activeStaffProvider lives here
import '../../features/auth/auth_provider.dart';    // ← profileProvider lives here

// ── Current open shift for the active staff member ────────────────────────────

final currentShiftProvider =
    AsyncNotifierProvider<CurrentShiftNotifier, CashierShift?>(
        CurrentShiftNotifier.new);

class CurrentShiftNotifier extends AsyncNotifier<CashierShift?> {
  @override
  Future<CashierShift?> build() async {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return null;
    final businessId = profile.businessId;
    if (businessId == null) return null;

    final staff = ref.watch(activeStaffProvider);
    if (staff == null) return null;

    return ref.read(shiftServiceProvider).getOpenShift(
          businessId: businessId,
          staffId: staff.id,
        );
  }

  Future<void> openShift({required double openingCash}) async {
    final profile = ref.read(profileProvider).value!;
    final staff = ref.read(activeStaffProvider)!;
    final businessId = profile.businessId!;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ref.read(shiftServiceProvider).openShift(
            businessId: businessId,
            staffId: staff.id,
            staffName: staff.name,
            openingCash: openingCash,
          );
    });
  }

  Future<CashierShift?> closeShift({
    required double actualCashCount,
    String? notes,
  }) async {
    final currentShift = state.value;
    if (currentShift == null) return null;

    final closed = await ref.read(shiftServiceProvider).closeShift(
          shiftId: currentShift.id,
          actualCashCount: actualCashCount,
          notes: notes,
        );

    state = const AsyncData(null);
    return closed;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

// ── Shift gate: does the current cashier have an open shift? ──────────────────

final hasOpenShiftProvider = Provider<bool>((ref) {
  return ref.watch(currentShiftProvider).value != null;
});