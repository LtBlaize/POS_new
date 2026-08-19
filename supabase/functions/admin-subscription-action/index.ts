// supabase/functions/admin-subscription-action/index.ts
//
// Phase 7. Multiplexed successor to admin-change-plan's pattern — same
// two-step auth (caller JWT check, then service_role write), same
// validate-before-any-DB-call discipline, but one function handling
// change_plan / extend / suspend / reactivate / cancel via an `action`
// field, instead of five near-duplicate files. If you'd rather keep them
// as separate functions for audit/log isolation, this is the one place
// that needs splitting — the SQL functions it calls are already separate.

import { serve } from "jsr:@std/http@1.0.12/server";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_PLANS = ["free", "pro", "enterprise"] as const;
const ALLOWED_ACTIONS = ["change_plan", "extend", "suspend", "reactivate", "cancel"] as const;
type Action = (typeof ALLOWED_ACTIONS)[number];

interface ActionBody {
  action: Action;
  business_id: string;
  new_plan?: string;        // required for change_plan / cancel(implicit 'free')
  trial_ends_at?: string;   // required for extend
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
  if (body.action === "change_plan" || body.action === "cancel") {
    const plan = body.action === "cancel" ? "free" : body.new_plan;
    if (!ALLOWED_PLANS.includes(plan as (typeof ALLOWED_PLANS)[number])) {
      return jsonRes({ error: `new_plan must be one of: ${ALLOWED_PLANS.join(", ")}` }, 400);
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
        p_metadata: metadata,
      }));
      break;
    }
    case "cancel": {
      ({ error: rpcError } = await serviceClient.rpc("admin_change_plan", {
        p_business_id: body.business_id,
        p_new_plan: "free",
        p_admin_user_id: adminRow.id,
        p_trial_ends_at: null,
        p_metadata: { ...metadata, cancelled: true },
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