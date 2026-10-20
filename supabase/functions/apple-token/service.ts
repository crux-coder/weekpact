export interface AppleTokenBackend {
  identify(token: string): Promise<string | null>;
  exchange(code: string): Promise<string | null>;
  save(userId: string, refreshToken: string): Promise<void>;
}

/** Stores the Apple refresh token for the signed-in user so deletion can revoke it. */
export async function storeAppleToken(token: string, payload: unknown, backend: AppleTokenBackend) {
  const code = (payload as { authorizationCode?: unknown } | null)?.authorizationCode;
  if (typeof code !== "string" || code.length === 0 || code.length > 4096) {
    return { status: 400, body: { error: "Authorization code required" } };
  }
  const userId = await backend.identify(token);
  if (!userId) return { status: 401, body: { error: "Your session is no longer valid" } };
  const refreshToken = await backend.exchange(code);
  if (!refreshToken) return { status: 400, body: { error: "Apple did not accept the authorization code" } };
  await backend.save(userId, refreshToken);
  return { status: 200, body: { stored: true } };
}
