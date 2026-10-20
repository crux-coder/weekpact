// Sign in with Apple's server API: exchanging an authorization code for a
// refresh token, and revoking that token when the account is deleted.
// https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens
// https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

export interface AppleConfig {
  teamId: string;
  keyId: string;
  clientId: string;
  /** The .p8 key from the Apple Developer portal, PEM encoded. */
  privateKey: string;
}

export type Fetch = (input: string, init: RequestInit) => Promise<Response>;

const APPLE = "https://appleid.apple.com";

export function appleConfigFromEnv(env: (name: string) => string | undefined): AppleConfig | null {
  const teamId = env("APPLE_TEAM_ID");
  const keyId = env("APPLE_KEY_ID");
  const clientId = env("APPLE_CLIENT_ID");
  const privateKey = env("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !clientId || !privateKey) return null;
  // Dashboards often store the key on one line with literal \n separators.
  return { teamId, keyId, clientId, privateKey: privateKey.replace(/\\n/g, "\n") };
}

const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encodeJson = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

/** The ES256 client secret Apple expects in place of a static secret. */
export async function appleClientSecret(config: AppleConfig, now = Date.now()): Promise<string> {
  const pem = config.privateKey.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const issued = Math.floor(now / 1000);
  const input = `${encodeJson({ alg: "ES256", kid: config.keyId, typ: "JWT" })}.${
    encodeJson({ iss: config.teamId, iat: issued, exp: issued + 300, aud: APPLE, sub: config.clientId })
  }`;
  // WebCrypto signs ECDSA as raw r||s, which is the JWS encoding.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input),
  );
  return `${input}.${base64url(new Uint8Array(signature))}`;
}

async function post(fetcher: Fetch, path: string, form: Record<string, string>) {
  return await fetcher(`${APPLE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
  });
}

/** The refresh token for a fresh authorization code, or null if Apple refuses it. */
export async function exchangeAppleCode(code: string, config: AppleConfig, fetcher: Fetch = fetch) {
  const response = await post(fetcher, "/auth/token", {
    client_id: config.clientId,
    client_secret: await appleClientSecret(config),
    code,
    grant_type: "authorization_code",
  });
  if (!response.ok) {
    await response.body?.cancel();
    return null;
  }
  const body = await response.json();
  return typeof body?.refresh_token === "string" && body.refresh_token ? body.refresh_token as string : null;
}

/** Whether Apple accepted the revocation. */
export async function revokeAppleToken(refreshToken: string, config: AppleConfig, fetcher: Fetch = fetch) {
  const response = await post(fetcher, "/auth/revoke", {
    client_id: config.clientId,
    client_secret: await appleClientSecret(config),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  await response.body?.cancel();
  return response.ok;
}
