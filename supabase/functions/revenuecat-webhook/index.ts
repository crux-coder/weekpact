import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { handleWebhook } from "./service.ts";

Deno.serve(async (request) => {
  const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers });
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  if (!url || !serviceKey) return respond({ error: "Webhook unavailable" }, 503);

  try {
    const payload = await request.json().catch(() => null);
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const result = await handleWebhook(
      request.headers.get("Authorization"),
      payload,
      secret,
      {
        async apply(body) {
          const { data, error } = await admin.rpc("apply_subscription_event", {
            payload: body,
          });
          if (error) throw error;
          return { outcome: (data as { outcome?: string })?.outcome ?? "applied" };
        },
      },
    );
    return respond(result.body, result.status);
  } catch (_) {
    // A 500 makes RevenueCat retry, which is what a transient database failure
    // needs. Upstream detail is never echoed back.
    return respond({ error: "Could not record the event" }, 500);
  }
});
