import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { corsHeaders } from "../invite-crew-member/cors.ts";
import { deleteAccount } from "./service.ts";

Deno.serve(async (request) => {
  const headers = { ...corsHeaders(), "Content-Type": "application/json", "Cache-Control": "no-store" };
  const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return respond({ error: "Authentication required" }, 401);
  try {
    const payload = await request.json();
    if (typeof payload?.password !== "string" || payload.password.length === 0 || payload.password.length > 4096) {
      return respond({ error: "Current password required" }, 400);
    }
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) return respond({ error: "Account deletion unavailable" }, 503);
    const options = { auth: { persistSession: false, autoRefreshToken: false } };
    const admin = createClient(url, serviceKey, options);
    const verifier = createClient(url, anonKey, options);
    const result = await deleteAccount(authorization.slice(7), payload.password, {
      async identify(token) {
        const { data, error } = await admin.auth.getUser(token);
        return error || !data.user?.email ? null : { id: data.user.id, email: data.user.email };
      },
      async verify(email, password) {
        const { data, error } = await verifier.auth.signInWithPassword({ email, password });
        if (error || !data.session) return null;
        // Password verification must not leave a second signed-in session behind.
        const { error: revokeError } = await admin.auth.admin.signOut(data.session.access_token, "local");
        if (revokeError) throw revokeError;
        return data.user.id;
      },
      async removeAvatar(id) {
        const { error } = await admin.storage.from("avatars").remove([`${id}/avatar.png`]);
        if (error) throw error;
      },
      async removeUser(id) {
        const { error } = await admin.auth.admin.deleteUser(id, false);
        if (error) throw error;
      },
    });
    return respond(result.body, result.status);
  } catch (_) {
    // Never log passwords, JWTs or potentially identifying upstream errors.
    return respond({ error: "Could not finish deletion. Please try again." }, 500);
  }
});
