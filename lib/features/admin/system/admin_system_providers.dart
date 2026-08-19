// lib/features/admin/system/admin_system_providers.dart
//
// Phase 11. Deliberately sparse. Per the plan: "real checks where feasible
// ... everything else explicitly marked 'not configured' rather than faked
// 'Operational.'" Only Supabase reachability is a real check right now —
// everything else is a static "not configured" entry until there's a real
// signal to check (e.g. sync_queue_service.dart's actual schema, which
// wasn't available when this was written).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CheckStatus { ok, degraded, down, notConfigured }

class SystemCheck {
  final String label;
  final CheckStatus status;
  final String detail;
  final Duration? latency;

  const SystemCheck({
    required this.label,
    required this.status,
    required this.detail,
    this.latency,
  });
}

final systemChecksProvider = FutureProvider.autoDispose<List<SystemCheck>>((ref) async {
  final checks = <SystemCheck>[];

  // ── Real check: Supabase reachability ───────────────────────────────────
  final sw = Stopwatch()..start();
  try {
    final client = Supabase.instance.client;
    // Cheapest possible round trip that still proves the DB is reachable
    // and RLS/auth is functioning for this session — reuses a table this
    // admin session can already read (RLS-permitted per Phase 2), rather
    // than adding a new health-check endpoint.
    await client.from('subscription_plans').select('id').limit(1);
    sw.stop();
    checks.add(SystemCheck(
      label: 'Supabase reachability',
      status: sw.elapsedMilliseconds < 1500 ? CheckStatus.ok : CheckStatus.degraded,
      detail: sw.elapsedMilliseconds < 1500 ? 'Responding normally' : 'Responding slowly',
      latency: sw.elapsed,
    ));
  } catch (e) {
    sw.stop();
    checks.add(SystemCheck(
      label: 'Supabase reachability',
      status: CheckStatus.down,
      detail: 'Query failed: $e',
      latency: sw.elapsed,
    ));
  }

  // ── Real check: auth session validity ───────────────────────────────────
  final session = Supabase.instance.client.auth.currentSession;
  if (session != null) {
    final expiresAt = session.expiresAt;
    final expiryDt = expiresAt != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
        : null;
    final stillValid = expiryDt == null || expiryDt.isAfter(DateTime.now());
    checks.add(SystemCheck(
      label: 'Admin session',
      status: stillValid ? CheckStatus.ok : CheckStatus.degraded,
      detail: stillValid
          ? 'Valid${expiryDt != null ? " until ${_fmtTime(expiryDt)}" : ""}'
          : 'Session expired — re-authentication may be needed',
    ));
  } else {
    checks.add(const SystemCheck(
      label: 'Admin session',
      status: CheckStatus.down,
      detail: 'No active session',
    ));
  }

  // ── Not configured: no real signal available yet ────────────────────────
  // Each of these needs a data source this codebase doesn't expose to the
  // admin client yet — listed honestly rather than guessed at:
  checks.addAll(const [
    SystemCheck(
      label: 'Device sync status',
      status: CheckStatus.notConfigured,
      detail: 'No central sync-status table — sync state lives per-device in local SQLite',
    ),
    SystemCheck(
      label: 'LAN server health',
      status: CheckStatus.notConfigured,
      detail: 'LAN servers run per-business, not reachable from the admin console',
    ),
    SystemCheck(
      label: 'PayMongo integration',
      status: CheckStatus.notConfigured,
      detail: 'Not yet integrated — see Phase 8/13 of the rollout plan',
    ),
    SystemCheck(
      label: 'Storage / image uploads',
      status: CheckStatus.notConfigured,
      detail: 'No health probe wired for Supabase Storage yet',
    ),
  ]);

  return checks;
});

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';