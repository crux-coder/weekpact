export interface DeletionUser {
  id: string;
  email: string | null;
  /** Auth identity providers, such as "email", "apple" and "google". */
  providers: string[];
}

export interface DeletionBackend {
  identify(token: string): Promise<DeletionUser | null>;
  verify(email: string, password: string): Promise<string | null>;
  removeAvatar(id: string): Promise<void>;
  removeCheckInPhotos(id: string): Promise<void>;
  appleRefreshToken(id: string): Promise<string | null>;
  revokeApple(refreshToken: string): Promise<void>;
  removeUser(id: string): Promise<void>;
}

export async function deleteAccount(token: string, payload: unknown, backend: DeletionBackend) {
  const { password, confirm } = (payload ?? {}) as { password?: unknown; confirm?: unknown };
  const user = await backend.identify(token);
  if (!user) return { status: 401, body: { error: "Your session is no longer valid" } };
  // Accounts with a password prove it; Apple and Google accounts have none, so
  // they type DELETE instead, behind the fresh session the app already holds.
  if (user.providers.includes("email")) {
    if (typeof password !== "string" || password.length === 0 || password.length > 4096 || !user.email) {
      return { status: 400, body: { error: "Current password required" } };
    }
    const verifiedId = await backend.verify(user.email, password);
    if (verifiedId !== user.id) return { status: 403, body: { error: "Incorrect password" } };
  } else if (confirm !== "DELETE") {
    return { status: 400, body: { error: "Type DELETE to confirm" } };
  }
  // Storage objects can block Auth deletion; failure here leaves the account intact.
  await backend.removeAvatar(user.id);
  await backend.removeCheckInPhotos(user.id);
  // Apple asks apps to revoke their tokens on deletion. A failure must not
  // keep someone from deleting their account, so it is noted and passed over.
  try {
    const appleToken = await backend.appleRefreshToken(user.id);
    if (appleToken) await backend.revokeApple(appleToken);
  } catch (_) {
    console.warn("delete-account: Apple token revocation failed");
  }
  await backend.removeUser(user.id);
  return { status: 200, body: { deleted: true } };
}
