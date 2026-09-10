import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";

import { createInviteEmailSender } from "./ses.ts";
import { corsHeaders } from "./cors.ts";
import { renderCrewInvite } from "./template.ts";

const jsonHeaders = { "Content-Type": "application/json" };

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(), ...jsonHeaders },
  });
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (request.method !== "POST") {
    return response({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return response({ error: "Authentication required" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const sendEmail = createInviteEmailSender(Deno.env.get);
    const fromEmail = Deno.env.get("EMAIL_FROM");
    const appBaseUrl = Deno.env.get("APP_BASE_URL") ?? "weekpact://invite";
    if (!supabaseUrl || !anonKey || !sendEmail || !fromEmail) {
      return response({ error: "Invite email is not configured" }, 500);
    }

    const payload = await request.json();
    const crewId = typeof payload.crewId === "string" ? payload.crewId : "";
    const email = typeof payload.email === "string"
      ? payload.email.trim().toLowerCase()
      : "";
    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    const uuidPattern =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(crewId) || !emailPattern.test(email)) {
      return response(
        { error: "A valid crew and email address are required" },
        400,
      );
    }

    const client = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = authorization.slice("Bearer ".length);
    const { data: authData, error: authError } = await client.auth.getUser(
      token,
    );
    if (authError || !authData.user) {
      return response({ error: "Your session is no longer valid" }, 401);
    }

    const { data: crew, error: crewError } = await client
      .from("crews")
      .select("id,name")
      .eq("id", crewId)
      .eq("owner_id", authData.user.id)
      .maybeSingle();
    if (crewError) throw crewError;
    if (!crew) {
      return response({ error: "Only the crew owner can invite people" }, 403);
    }

    const { data: existingMember, error: memberError } = await client
      .from("crew_members")
      .select("user_id")
      .eq("crew_id", crewId)
      .eq("email", email)
      .maybeSingle();
    if (memberError) throw memberError;
    if (existingMember) {
      return response({ error: "That person is already in this crew" }, 409);
    }

    const { data: pendingInvite, error: pendingInviteError } = await client
      .from("crew_invites")
      .select("created_at")
      .eq("crew_id", crewId)
      .eq("email", email)
      .is("accepted_at", null)
      .maybeSingle();
    if (pendingInviteError) throw pendingInviteError;
    if (
      pendingInvite &&
      Date.now() - new Date(pendingInvite.created_at).getTime() < 60_000
    ) {
      return response(
        { error: "Please wait a minute before resending this invite" },
        429,
      );
    }

    const rawToken = `${crypto.randomUUID()}${crypto.randomUUID()}`.replaceAll(
      "-",
      "",
    );
    const tokenHash = await sha256(rawToken);
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
      .toISOString();
    const { data: invite, error: inviteError } = await client
      .from("crew_invites")
      .upsert(
        {
          crew_id: crewId,
          email,
          token_hash: tokenHash,
          invited_by: authData.user.id,
          expires_at: expiresAt,
          accepted_at: null,
          created_at: new Date().toISOString(),
        },
        { onConflict: "crew_id,email" },
      )
      .select("id")
      .single();
    if (inviteError) throw inviteError;

    const inviteUrl = new URL(appBaseUrl);
    inviteUrl.searchParams.set("invite", rawToken);
    const message = renderCrewInvite(crew.name, email, inviteUrl.toString());
    try {
      await sendEmail({
        from: fromEmail,
        to: email,
        subject: `Join ${crew.name} on WeekPact`,
        ...message,
      });
    } catch (error) {
      // Match the token as well: a failed send must not delete a newer invite.
      const { error: cleanupError } = await client.from("crew_invites")
        .delete().eq("id", invite.id).eq("token_hash", tokenHash);
      if (cleanupError) {
        console.error("Failed to clean up unsent invite", cleanupError.code);
      }
      // Avoid logging the message body, invite token, or AWS credentials.
      console.error(
        "SES failed to send crew invite",
        error instanceof Error ? error.name : "UnknownError",
      );
      return response({ error: "The invite could not be emailed" }, 502);
    }

    return response({ inviteId: invite.id, expiresAt }, 201);
  } catch (error) {
    console.error("Unexpected crew invite error", error);
    return response({ error: "Unable to send invite" }, 500);
  }
});
