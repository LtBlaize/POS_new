// lib/core/config/access_enforcement_flag.dart
//
// Single on/off switch for POS-shell subscription enforcement (Gap A).
//
// MUST stay false until ALL of the following are confirmed:
//   1. Migration 2026090803 applied (subscription_expires_at column exists)
//   2. completeRegistration() no longer sends trial dates client-side
//   3. Every existing business has been backfilled through the admin
//      Change Plan dialog with a real plan + duration (or is genuinely
//      on an active trial)
//   4. hasCoreAccess has been spot-checked against real business rows —
//      active/trial/expired/missing-data cases all resolve as expected
//
// Flipping this to true before all four are done WILL lock out real,
// paying customers with no warning — see the original Gap A audit.
const bool kEnforceCoreAccess = false;