// supabase/functions/admin-manage-admins/index.ts
//
// Phase 12. Same two-step pattern as admin-change-plan / admin-subscription-action.
// Scoped to platform_admin only (not platform_support/viewer) — this
// function can deactivate other admins, so the authorization check requires
// the specific role, not just "any active admin".
//
// 'invite' is a stub: creating + inviting a new Supabase Auth user needs an
// email-sending path (admin.inviteUserByEmail or a magic-link flow) that
// isn't wired up yet. Returns 501 so the UI shows a clear message instead
// of silently failing or pretending to succeed.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_ACTIONS = ["deactivate", "reactivate", "set_role", "invite"] as const;
type Action = (typeof ALLOWED_ACTIONS)[number];
const ALLOWED_ROLES = ["platform_admin", "platform_support", "platform_viewer"] as const;

interface ManageAdminsBody {
  action: Action;
  target_admin_id?: string; // required for deactivate/reactivate/set_role
  role?: string;             // required for set_role
  email?: string;            // 'invite' only (unused while stubbed)
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

  let body: ManageAdminsBody;
  try {
    body = await req.json();
  } catch {
    return jsonRes({ error: "invalid JSON body" }, 400);
  }

  if (!ALLOWED_ACTIONS.includes(body.action)) {
    return jsonRes({ error: `action must be one of: ${ALLOWED_ACTIONS.join(", ")}` }, 400);
  }

  // --- 'invite' stub -------------------------------------------------------
  if (body.action === "invite") {
    return jsonRes(
      { error: "Inviting new admins isn't available yet — add them directly in Supabase Auth for now." },
      501,
    );
  }

  if (!isUuid(body.target_admin_id)) {
    return jsonRes({ error: "target_admin_id must be a uuid" }, 400);
  }
  if (body.action === "set_role" && !ALLOWED_ROLES.includes(body.role as (typeof ALLOWED_ROLES)[number])) {
    return jsonRes({ error: `role must be one of: ${ALLOWED_ROLES.join(", ")}` }, 400);
  }

  // --- Step 1: identity + authorization check, as the caller -------------
  // required_role: "platform_admin" — not null. This differs from most
  // other /admin/* checks, which accept any active admin.
  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await callerClient.auth.getUser();
  if (userError || !user) return jsonRes({ error: "invalid or expired session" }, 401);

  const { data: isAdmin, error: adminCheckError } = await callerClient.rpc(
    "is_platform_admin",
    { required_role: "platform_admin" },
  );
  if (adminCheckError || !isAdmin) {
    return jsonRes({ error: "forbidden: platform_admin required" }, 403);
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

  const { error: rpcError } = await serviceClient.rpc("admin_manage_admin_user", {
    p_target_admin_id: body.target_admin_id,
    p_action: body.action,
    p_admin_user_id: adminRow.id,
    p_role: body.action === "set_role" ? body.role : null,
    p_metadata: metadata,
  });

  if (rpcError) {
    console.error(`${body.action} failed:`, rpcError);
    // Guardrail violations (self-deactivate, last-admin) come back as plain
    // Postgres exception messages — surface them, since they're meant to
    // be read by the admin, not swallowed into a generic 500.
    return jsonRes({ error: rpcError.message ?? `failed to ${body.action}` }, 400);
  }

  return jsonRes({ ok: true }, 200);
});