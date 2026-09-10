import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { createFcmSender } from "./fcm.ts";
import { renderNotification } from "./templates.ts";

let sender: ReturnType<typeof createFcmSender> | undefined;
Deno.serve(async (request) => {
  const expected = Deno.env.get("NOTIFICATION_DISPATCH_SECRET");
  if (!expected || request.headers.get("x-notification-secret") !== expected) return new Response("Unauthorized", { status: 401 });
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const credentials = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!credentials) return new Response("Notification sender is not configured", { status: 503 });
  try {
    sender ??= createFcmSender(JSON.parse(credentials));
    const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data: jobs, error } = await client.rpc("claim_notification_deliveries", { batch_size: 20 });
    if (error) throw new Error("claim_failed");
    const counts = { sent: 0, retry: 0, failed: 0, unregistered: 0 };
    // Bound concurrency and duration so leases outlive normal processing.
    for (let offset = 0; offset < jobs.length; offset += 5) {
      await Promise.all(jobs.slice(offset, offset + 5).map(async (job: Parameters<typeof renderNotification>[0] & { device_token: string; delivery_id: string; lease: string }) => {
        let content;
        try { content = renderNotification(job); } catch (_) { content = null; }
        const result = content ? await sender!(job.device_token, content) : { outcome: "failed", code: "unsupported_notification_type" };
        const { error: finishError } = await client.rpc("finish_notification_delivery", {
          delivery: job.delivery_id, lease: job.lease, outcome: result.outcome, failure_code: result.code ?? null,
        });
        if (finishError) throw new Error("finish_failed");
        counts[result.outcome as keyof typeof counts]++;
      }));
    }
    return Response.json(counts);
  } catch (_) {
    // Never log credentials, registration tokens, or notification content.
    return Response.json({ error: "Notification dispatch failed; queued jobs will retry." }, { status: 500 });
  }
});
