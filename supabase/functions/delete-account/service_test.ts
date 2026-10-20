import { deleteAccount, type DeletionBackend, type DeletionUser } from './service.ts';
function assert(value: unknown, message = 'Assertion failed'): asserts value { if (!value) throw new Error(message); }
const emailUser: DeletionUser = { id: 'owner', email: 'owner@example.com', providers: ['email'] };
const appleUser: DeletionUser = { id: 'owner', email: 'relay@privaterelay.appleid.com', providers: ['apple'] };
function fixture(user: DeletionUser = emailUser, appleToken: string | null = null) {
  const calls: string[] = [];
  const backend: DeletionBackend = {
    async identify(token) { calls.push(`identify:${token}`); return user; },
    async verify(email) { calls.push(`verify:${email}`); return 'owner'; },
    async removeCheckInPhotos(id) { calls.push(`photos:${id}`); },
    async removeAvatar(id) { calls.push(`avatar:${id}`); },
    async appleRefreshToken(id) { calls.push(`apple-token:${id}`); return appleToken; },
    async revokeApple(token) { calls.push(`revoke:${token}`); },
    async removeUser(id) { calls.push(`user:${id}`); },
  };
  return { backend, calls };
}
const password = { password: 'password' };
const confirmed = { confirm: 'DELETE' };
Deno.test('deletes only the authenticated and password-verified account, storage first', async () => {
  const { backend, calls } = fixture();
  assert((await deleteAccount('token', password, backend)).status === 200);
  assert(calls.join(',') === 'identify:token,verify:owner@example.com,avatar:owner,photos:owner,apple-token:owner,user:owner');
});
Deno.test('invalid session cannot reach password verification or deletion', async () => {
  const { backend, calls } = fixture(); backend.identify = async () => null;
  assert((await deleteAccount('token', password, backend)).status === 401);
  assert(calls.length === 0);
});
for (const verified of [null, 'another-user']) {
  Deno.test(`wrong password or identity (${verified}) cannot delete`, async () => {
    const { backend, calls } = fixture(); backend.verify = async () => verified;
    assert((await deleteAccount('token', password, backend)).status === 403);
    assert(calls.length === 1);
  });
}
for (const body of [{}, confirmed, { password: '' }, { password: 7 }, { password: 'x'.repeat(4097) }, null]) {
  Deno.test(`email accounts need their password, not DELETE (${JSON.stringify(body)?.slice(0, 30)})`, async () => {
    const { backend, calls } = fixture();
    const result = await deleteAccount('token', body, backend);
    assert(result.status === 400 && result.body.error === 'Current password required');
    assert(calls.join(',') === 'identify:token');
  });
}
Deno.test('an email account linked to Apple still needs the password', async () => {
  const { backend, calls } = fixture({ ...emailUser, providers: ['apple', 'email'] });
  assert((await deleteAccount('token', confirmed, backend)).status === 400);
  assert(!calls.includes('user:owner'));
});
for (const provider of ['apple', 'google']) {
  Deno.test(`${provider} accounts delete by typing DELETE, without a password check`, async () => {
    const { backend, calls } = fixture({ ...appleUser, providers: [provider] });
    assert((await deleteAccount('token', confirmed, backend)).status === 200);
    assert(!calls.some(c => c.startsWith('verify:')));
    assert(calls.at(-1) === 'user:owner');
  });
}
for (const body of [{}, { confirm: 'delete' }, { confirm: 'DELETE ' }, password, null]) {
  Deno.test(`Apple and Google accounts need DELETE exactly (${JSON.stringify(body)})`, async () => {
    const { backend, calls } = fixture(appleUser);
    const result = await deleteAccount('token', body, backend);
    assert(result.status === 400 && result.body.error === 'Type DELETE to confirm');
    assert(calls.join(',') === 'identify:token');
  });
}
Deno.test('a stored Apple token is revoked after storage and before the user is removed', async () => {
  const { backend, calls } = fixture(appleUser, 'refresh-1');
  assert((await deleteAccount('token', confirmed, backend)).status === 200);
  assert(calls.join(',') === 'identify:token,avatar:owner,photos:owner,apple-token:owner,revoke:refresh-1,user:owner');
});
Deno.test('Apple revocation failure does not block deletion and logs no token', async () => {
  for (const fail of ['lookup', 'revoke']) {
    const { backend, calls } = fixture(appleUser, 'refresh-secret');
    if (fail === 'lookup') backend.appleRefreshToken = async () => { throw new Error('refresh-secret'); };
    else backend.revokeApple = async () => { throw new Error('refresh-secret'); };
    const logged: unknown[] = [];
    const warn = console.warn, error = console.error;
    console.warn = console.error = (...args: unknown[]) => { logged.push(...args); };
    try {
      assert((await deleteAccount('token', confirmed, backend)).status === 200);
    } finally { console.warn = warn; console.error = error; }
    assert(calls.at(-1) === 'user:owner');
    assert(logged.length === 1 && !JSON.stringify(logged).includes('refresh-secret'));
  }
});
Deno.test('storage failure preserves auth account and is retryable', async () => {
  const { backend, calls } = fixture();
  backend.removeAvatar = async () => { throw new Error('offline'); };
  let failed = false;
  try { await deleteAccount('token', password, backend); } catch { failed = true; }
  assert(failed); assert(!calls.includes('user:owner'));
  backend.removeAvatar = async () => {};
  assert((await deleteAccount('token', password, backend)).status === 200);
});
Deno.test('auth deletion failure never reports success', async () => {
  const { backend } = fixture(); backend.removeUser = async () => { throw new Error('database failed'); };
  let failed = false;
  try { await deleteAccount('token', password, backend); } catch { failed = true; }
  assert(failed);
});
Deno.test('check-in photo deletion failure preserves the account for retry', async () => {
  const { backend, calls } = fixture();
  backend.removeCheckInPhotos = async () => { throw new Error('offline'); };
  let failed = false;
  try { await deleteAccount('token', password, backend); } catch { failed = true; }
  assert(failed); assert(!calls.includes('user:owner'));
  assert(!calls.some(c => c.startsWith('revoke:')));
});
