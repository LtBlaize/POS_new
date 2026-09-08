// supabase/functions/admin-subscription-action/index.ts
//
// Phase 7. Multiplexed successor to admin-change-plan's pattern — same
// two-step auth (caller JWT check, then service_role write), same
// validate-before-any-DB-call discipline, but one function handling
// change_plan / extend / suspend / reactivate via an `action` field,
// instead of five near-duplicate files. If you'd rather keep them as
// separate functions for audit/log isolation, this is the one place that
// needs splitting — the SQL functions it calls are already separate.
//
// `cancel` was removed as a distinct action (2026-09): it previously
// defaulted new_plan to 'free', a plan tier that no longer exists in the
// starter/growth/pro model. Cancelling a subscription with no free tier to
// fall back to is the same operation as `suspend` (admin_set_business_active
// false) — it doesn't need its own plan-change RPC call. Use `suspend`.

import { serve } from "jsr:@std/http@1.0.12/server";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Keep this in sync with the `subscription_plan` Postgres enum.
const ALLOWED_PLANS = ["starter", "growth", "pro"] as const;
const ALLOWED_ACTIONS = ["change_plan", "extend", "suspend", "reactivate"] as const;
type Action = (typeof ALLOWED_ACTIONS)[number];

interface ActionBody {
  action: Action;
  business_id: string;
  new_plan?: string;         // required for change_plan
  trial_ends_at?: string;    // required for extend
  duration_months?: number;  // optional for change_plan — paid access duration
  reason?: string;
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  );
}

function jsonRes(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method !== "POST") return jsonRes({ error: "method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonRes({ error: "missing Authorization header" }, 401);

  let body: ActionBody;
  try {
    body = await req.json();
  } catch {
    return jsonRes({ error: "invalid JSON body" }, 400);
  }

  // --- Validation, before any DB call -------------------------------------
  if (!ALLOWED_ACTIONS.includes(body.action)) {
    return jsonRes({ error: `action must be one of: ${ALLOWED_ACTIONS.join(", ")}` }, 400);
  }
  if (!isUuid(body.business_id)) {
    return jsonRes({ error: "business_id must be a uuid" }, 400);
  }
  if (body.action === "change_plan") {
    if (!ALLOWED_PLANS.includes(body.new_plan as (typeof ALLOWED_PLANS)[number])) {
      return jsonRes({ error: `new_plan must be one of: ${ALLOWED_PLANS.join(", ")}` }, 400);
    }
    if (body.duration_months !== undefined) {
      if (
        !Number.isInteger(body.duration_months) ||
        body.duration_months <= 0 ||
        body.duration_months > 24
      ) {
        return jsonRes({ error: "duration_months must be a positive integer, max 24" }, 400);
      }
    }
  }
  if (body.action === "extend") {
    if (!body.trial_ends_at || Number.isNaN(Date.parse(body.trial_ends_at))) {
      return jsonRes({ error: "trial_ends_at must be a valid ISO timestamp" }, 400);
    }
  }

  // --- Step 1: identity + authorization check, as the caller -------------
  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await callerClient.auth.getUser();
  if (userError || !user) return jsonRes({ error: "invalid or expired session" }, 401);

  const { data: isAdmin, error: adminCheckError } = await callerClient.rpc(
    "is_platform_admin",
    { required_role: null },
  );
  if (adminCheckError || !isAdmin) {
    return jsonRes({ error: "forbidden: platform admin required" }, 403);
  }

  const { data: adminRow, error: adminRowError } = await callerClient
    .from("admin_users")
    .select("id")
    .eq("auth_user_id", user.id)
    .single();
  if (adminRowError || !adminRow) {
    return jsonRes({ error: "admin record not found" }, 403);
  }

  // --- Step 2: privileged write, as service_role -------------------------
  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const metadata = body.reason ? { reason: body.reason } : {};

  let rpcError;
  switch (body.action) {
    case "change_plan": {
      ({ error: rpcError } = await serviceClient.rpc("admin_change_plan", {
        p_business_id: body.business_id,
        p_new_plan: body.new_plan,
        p_admin_user_id: adminRow.id,
        p_trial_ends_at: body.trial_ends_at ?? null,
        p_duration_months: body.duration_months ?? null,
        p_metadata: metadata,
      }));
      break;
    }
    case "extend": {
      ({ error: rpcError } = await serviceClient.rpc("admin_extend_trial", {
        p_business_id: body.business_id,
        p_admin_user_id: adminRow.id,
        p_trial_ends_at: body.trial_ends_at,
        p_metadata: metadata,
      }));
      break;
    }
    case "suspend":
    case "reactivate": {
      ({ error: rpcError } = await serviceClient.rpc("admin_set_business_active", {
        p_business_id: body.business_id,
        p_admin_user_id: adminRow.id,
        p_is_active: body.action === "reactivate",
        p_metadata: metadata,
      }));
      break;
    }
  }

  if (rpcError) {
    console.error(`${body.action} failed:`, rpcError);
    return jsonRes({ error: `failed to ${body.action}` }, 500);
  }

  return jsonRes({ ok: true }, 200);
});