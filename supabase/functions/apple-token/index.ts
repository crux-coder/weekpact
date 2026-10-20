import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { appleConfigFromEnv, exchangeAppleCode } from "../_shared/apple.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { storeAppleToken } from "./service.ts";

Deno.serve(async (request) => {
  const headers = { ...corsHeaders(), "Content-Type": "application/json", "Cache-Control": "no-store" };
  const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return respond({ error: "Authentication required" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apple = appleConfigFromEnv((name) => Deno.env.get(name));
  if (!url || !serviceKey || !apple) return respond({ error: "Apple token storage unavailable" }, 503);
  try {
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const result = await storeAppleToken(authorization.slice(7), await request.json(), {
      async identify(token) {
        const { data, error } = await admin.auth.getUser(token);
        return error || !data.user ? null : data.user.id;
      },
      exchange: (code) => exchangeAppleCode(code, apple),
      async save(userId, refreshToken) {
        const { error } = await admin.rpc("save_apple_refresh_token", { p_user: userId, p_refresh_token: refreshToken });
        if (error) throw error;
      },
    });
    return respond(result.body, result.status);
  } catch (_) {
    // Never log authorization codes, refresh tokens, JWTs or upstream errors.
    console.error("apple-token: could not store the Apple token");
    return respond({ error: "Could not store the Apple token. Please try again." }, 500);
  }
});
