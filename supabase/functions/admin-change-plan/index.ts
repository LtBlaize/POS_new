// supabase/functions/admin-change-plan/index.ts
//
// Phase 2 proof-of-concept Edge Function. This is the pattern Phase 7
// (subscription actions) and Phase 8 (payments) are meant to reuse:
//
//   1. Build a Supabase client scoped to the CALLER's own JWT (not service
//      role) and use it to check is_platform_admin(). This is the actual
//      authorization check — it runs as the caller, so RLS/the function's
//      own logic apply exactly as they would for any other query the caller
//      makes.
//   2. Only if that check passes, build a second client using the
//      service_role key and use it to perform the privileged write via the
//      admin_change_plan() SQL function (which is itself locked to
//      service_role — see phase2_admin_rls_and_helper.sql).
//
// Never skip step 1. Never let the service-role client touch a request body
// value without validating it first — see validation below.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Keep this in sync with the `subscription_plan` Postgres enum. There's no
// clean way to introspect an enum from inside an Edge Function at request
// time without an extra round trip, so it's duplicated here deliberately —
// update both places if the enum ever changes.
const ALLOWED_PLANS = ["free", "pro", "enterprise"] as const;

interface ChangePlanBody {
  business_id: string;
  new_plan: string;
  trial_ends_at?: string; // ISO 8601, optional
  reason?: string;
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  );
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "missing Authorization header" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  let body: ChangePlanBody;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid JSON body" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // --- Input validation, before any DB call -------------------------------
  if (!isUuid(body.business_id)) {
    return new Response(JSON.stringify({ error: "business_id must be a uuid" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!ALLOWED_PLANS.includes(body.new_plan as (typeof ALLOWED_PLANS)[number])) {
    return new Response(
      JSON.stringify({ error: `new_plan must be one of: ${ALLOWED_PLANS.join(", ")}` }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }
  if (body.trial_ends_at !== undefined && Number.isNaN(Date.parse(body.trial_ends_at))) {
    return new Response(JSON.stringify({ error: "trial_ends_at must be a valid ISO timestamp" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // --- Step 1: identity + authorization check, as the caller -------------
  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await callerClient.auth.getUser();

  if (userError || !user) {
    return new Response(JSON.stringify({ error: "invalid or expired session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const { data: isAdmin, error: adminCheckError } = await callerClient.rpc(
    "is_platform_admin",
    { required_role: null },
  );

  if (adminCheckError || !isAdmin) {
    return new Response(JSON.stringify({ error: "forbidden: platform admin required" }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }

  // Resolve the caller's admin_users.id (the FK target for
  // admin_activity_logs.admin_user_id) — not the same as auth.uid().
  const { data: adminRow, error: adminRowError } = await callerClient
    .from("admin_users")
    .select("id")
    .eq("auth_user_id", user.id)
    .single();

  if (adminRowError || !adminRow) {
    return new Response(JSON.stringify({ error: "admin record not found" }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }

  // --- Step 2: privileged write, as service_role -------------------------
  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { error: rpcError } = await serviceClient.rpc("admin_change_plan", {
    p_business_id: body.business_id,
    p_new_plan: body.new_plan,
    p_admin_user_id: adminRow.id,
    p_trial_ends_at: body.trial_ends_at ?? null,
    p_metadata: body.reason ? { reason: body.reason } : {},
  });

  if (rpcError) {
    console.error("admin_change_plan failed:", rpcError);
    return new Response(JSON.stringify({ error: "failed to change plan" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});