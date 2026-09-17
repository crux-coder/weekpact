/// Pure webhook handling: authorization, shape checks and the decision about
/// whether an event is worth handing to Postgres. Kept free of Deno and
/// Supabase so it can be tested without either.

export interface WebhookBackend {
  apply(payload: unknown): Promise<{ outcome: string }>;
}

export interface WebhookResult {
  status: number;
  body: Record<string, unknown>;
}

/// Constant-time comparison, so a wrong secret cannot be discovered one
/// character at a time by timing the response.
export function secretMatches(provided: string | null, expected: string): boolean {
  if (!provided || provided.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i += 1) {
    difference |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return difference === 0;
}

export async function handleWebhook(
  authorization: string | null,
  body: unknown,
  expectedSecret: string,
  backend: WebhookBackend,
): Promise<WebhookResult> {
  // RevenueCat sends whatever header value is configured in the dashboard, so
  // an unconfigured function must reject everything rather than accept anyone.
  if (!expectedSecret) return { status: 503, body: { error: "Webhook not configured" } };
  if (!secretMatches(authorization, expectedSecret)) {
    return { status: 401, body: { error: "Unauthorized" } };
  }

  const event = (body as { event?: unknown })?.event;
  if (!event || typeof event !== "object") {
    return { status: 400, body: { error: "Missing event" } };
  }

  const { outcome } = await backend.apply(body);
  // Everything understood answers 200. A non-2xx makes RevenueCat retry, which
  // is only wanted for failures the retry could actually fix.
  return { status: 200, body: { outcome } };
}
