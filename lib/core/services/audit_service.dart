// lib/core/services/audit_service.dart
//
// Write-only audit log service. Logs are immutable — no update or delete.
// Fails silently so audit errors never block the user action that triggered them.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_provider.dart';
import '../models/staff.dart';
import '../providers/staff_provider.dart';
import 'package:uuid/uuid.dart';
import 'connectivity_service.dart';
import 'sync_queue_service.dart';

// ── Action type constants ─────────────────────────────────────────────────────

class AuditAction {
  static const voidItem        = 'void_item';
  static const voidOrder       = 'void_order';
  static const discountApplied = 'discount_applied';
  static const managerOverride = 'manager_override';
  static const priceOverride   = 'price_override';
  static const shiftOpen       = 'shift_open';
  static const shiftClose      = 'shift_close';
  static const staffLogin      = 'staff_login';
  static const staffLogout     = 'staff_logout';
  static const settingsChanged = 'settings_changed';
  static const orderRefund     = 'order_refund';
  static const inventoryAdjust = 'inventory_adjust';
  static const creditAdded     = 'credit_added';
  static const creditPaid      = 'credit_paid';
}

// ── Provider ──────────────────────────────────────────────────────────────────

final auditServiceProvider = Provider<AuditService>((ref) {
  return AuditService(ref);
});

// ── Service ───────────────────────────────────────────────────────────────────

class AuditService {
  final Ref _ref;
  AuditService(this._ref);

  /// Logs an action. Never throws — errors are swallowed so audit failures
  /// never block the action that triggered them.
  Future<void> log({
    required String actionType,
    required String description,
    String? entityType,
    String? entityId,
    StaffMember? authorisedBy,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final businessId = _ref.read(profileProvider).asData?.value?.businessId;
      if (businessId == null) return;

      final actor = _ref.read(activeStaffProvider);
      if (actor == null) return;

      final row = {
        'id': const Uuid().v4(),
        'business_id': businessId,
        'performed_by_staff_id': actor.id,
        'performed_by_staff_name': actor.name,
        'performed_by_role': actor.role.value,
        'authorised_by_staff_id': authorisedBy?.id,
        'authorised_by_staff_name': authorisedBy?.name,
        'action_type': actionType,
        'entity_type': entityType,
        'entity_id': entityId,
        'description': description,
        'metadata': metadata,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_ref.read(isOnlineProvider)) {
        try {
          await Supabase.instance.client
              .from('audit_logs')
              .insert(row)
              .timeout(const Duration(seconds: 4));
          return;
        } catch (_) {}
      }
      await _ref.read(syncQueueServiceProvider).enqueue(
            operation: 'insert_audit_log',
            tableName: 'audit_logs',
            recordId: row['id'] as String,
            payload: row,
          );
    } catch (e) {
      // Intentionally silent — audit must never block user actions
    }
  }
}