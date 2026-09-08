// lib/core/utils/subscription_expiry_preview.dart
//
// Client-side mirror of the admin_change_plan RPC's expiration math, for
// preview purposes ONLY. This is not authoritative — the RPC recalculates
// GREATEST(now(), current_expiry) + N months server-side when it actually
// runs, using the DB's clock, not this device's. Never use this value for
// anything except the "Expires: ..." preview text in the confirm dialog.
class SubscriptionExpiryPreview {
  /// Returns the previewed subscription_expires_at, or null if this change
  /// wouldn't touch it at all (durationMonths == null → "No change").
  static DateTime? calculate({
    required DateTime? currentExpiresAt,
    required int? durationMonths,
  }) {
    if (durationMonths == null) return null;

    final now = DateTime.now();
    final base = (currentExpiresAt != null && currentExpiresAt.isAfter(now))
        ? currentExpiresAt
        : now;

    // Dart's DateTime constructor normalizes month overflow (e.g. month 14
    // becomes Feb of the following year), matching Postgres's
    // `+ interval 'N months'` rollover behavior.
    return DateTime(
      base.year,
      base.month + durationMonths,
      base.day,
      base.hour,
      base.minute,
      base.second,
    );
  }
}