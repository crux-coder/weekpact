export interface DeletionBackend {
  identify(token: string): Promise<{ id: string; email: string } | null>;
  verify(email: string, password: string): Promise<string | null>;
  removeAvatar(id: string): Promise<void>;
  removeCheckInPhotos(id: string): Promise<void>;
  removeUser(id: string): Promise<void>;
}

export async function deleteAccount(token: string, password: string, backend: DeletionBackend) {
  const user = await backend.identify(token);
  if (!user) return { status: 401, body: { error: "Your session is no longer valid" } };
  const verifiedId = await backend.verify(user.email, password);
  if (verifiedId !== user.id) return { status: 403, body: { error: "Incorrect password" } };
  // Storage objects can block Auth deletion; failure here leaves the account intact.
  await backend.removeAvatar(user.id);
  await backend.removeCheckInPhotos(user.id);
  await backend.removeUser(user.id);
  return { status: 200, body: { deleted: true } };
}
