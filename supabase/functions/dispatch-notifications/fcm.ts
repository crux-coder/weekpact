import type { PushContent } from "./templates.ts";

export type ServiceAccount = { project_id: string; client_email: string; private_key: string };
export type SendResult = { outcome: "sent" | "retry" | "failed" | "unregistered"; code?: string };
const encode = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const json = (value: unknown) => encode(new TextEncoder().encode(JSON.stringify(value)));

export function createFcmSender(account: ServiceAccount, request: typeof fetch = fetch) {
  if (!/^[a-z][a-z0-9-]{4,62}$/.test(account.project_id) || !account.client_email || !account.private_key) {
    throw new Error("invalid_firebase_service_account");
  }
  let cached: { token: string; expires: number } | undefined;
  let pending: Promise<string> | undefined;
  async function mintToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    const content = `${json({ alg: "RS256", typ: "JWT" })}.${json({
      iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
    })}`;
    const der = Uint8Array.from(atob(account.private_key.replace(/-----[^-]+-----|\s/g, "")), c => c.charCodeAt(0));
    const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(content));
    const response = await request("https://oauth2.googleapis.com/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${content}.${encode(new Uint8Array(signature))}` }),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error(`oauth_${response.status}`);
    const result = await response.json();
    if (typeof result.access_token !== "string" || typeof result.expires_in !== "number") throw new Error("invalid_oauth_response");
    cached = { token: result.access_token, expires: Date.now() + result.expires_in * 1000 };
    return cached.token;
  }
  async function accessToken() {
    if (cached && cached.expires > Date.now() + 60000) return cached.token;
    pending ??= mintToken().finally(() => { pending = undefined; });
    return pending;
  }
  return async (deviceToken: string, content: PushContent, validateOnly = false): Promise<SendResult> => {
    try {
      const response = await request(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
        method: "POST", headers: { "Authorization": `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
        body: JSON.stringify({ validate_only: validateOnly, message: {
          token: deviceToken, notification: { title: content.title, body: content.body }, data: content.data,
          android: { priority: "high", ttl: "86400s", notification: { channel_id: "weekpact_general", tag: content.data.notification_id } },
          apns: { headers: { "apns-push-type": "alert", "apns-priority": "10", "apns-collapse-id": content.data.notification_id },
            payload: { aps: { sound: "default" } } },
        } }), signal: AbortSignal.timeout(10000),
      });
      if (response.ok) return { outcome: "sent" };
      const result = await response.json().catch(() => ({}));
      const code = result.error?.details?.find((d: { "@type"?: string }) => d["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError")?.errorCode;
      if (code === "UNREGISTERED") return { outcome: "unregistered", code };
      if (response.status === 401) cached = undefined;
      if ([401,403,429].includes(response.status) || response.status >= 500) return { outcome: "retry", code: code ?? `http_${response.status}` };
      return { outcome: "failed", code: code ?? `http_${response.status}` };
    } catch (_) {
      return { outcome: "retry", code: "transport_or_auth_error" };
    }
  };
}
