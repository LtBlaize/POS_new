// supabase/functions/admin-record-payment/index.ts
//
// Phase 8. Same two-step pattern as admin-change-plan / admin-subscription-action:
// caller-JWT auth check first, then service_role write. Manual payments only
// — provider is hardcoded server-side to 'manual', never trusts a client-sent
// provider value (that's the whole point of keeping PayMongo out of this phase).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_STATUSES = ["pending", "completed", "failed", "refunded"] as const;

interface RecordPaymentBody {
  business_id: string;
  amount: number;
  currency?: string;
  status: string;
  reference?: string;
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

  let body: RecordPaymentBody;
  try {
    body = await req.json();
  } catch {
    return jsonRes({ error: "invalid JSON body" }, 400);
  }

  // --- Validation ----------------------------------------------------------
  if (!isUuid(body.business_id)) {
    return jsonRes({ error: "business_id must be a uuid" }, 400);
  }
  if (typeof body.amount !== "number" || !(body.amount > 0)) {
    return jsonRes({ error: "amount must be a positive number" }, 400);
  }
  if (!ALLOWED_STATUSES.includes(body.status as (typeof ALLOWED_STATUSES)[number])) {
    return jsonRes({ error: `status must be one of: ${ALLOWED_STATUSES.join(", ")}` }, 400);
  }
  const currency = body.currency ?? "PHP";
  if (typeof currency !== "string" || currency.length !== 3) {
    return jsonRes({ error: "currency must be a 3-letter code" }, 400);
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

  const { data: paymentId, error: rpcError } = await serviceClient.rpc("admin_record_payment", {
    p_business_id: body.business_id,
    p_admin_user_id: adminRow.id,
    p_amount: body.amount,
    p_currency: currency,
    p_status: body.status,
    p_reference: body.reference ?? null,
    p_metadata: body.reason ? { reason: body.reason } : {},
  });

  if (rpcError) {
    console.error("admin_record_payment failed:", rpcError);
    return jsonRes({ error: "failed to record payment" }, 500);
  }

  return jsonRes({ ok: true, payment_id: paymentId }, 200);
});