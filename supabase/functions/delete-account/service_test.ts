import { deleteAccount, type DeletionBackend } from './service.ts';
function assert(value: unknown, message = 'Assertion failed'): asserts value { if (!value) throw new Error(message); }
function fixture() {
  const calls: string[] = [];
  const backend: DeletionBackend = {
    async identify(token) { calls.push(`identify:${token}`); return { id: 'owner', email: 'owner@example.com' }; },
    async verify(email) { calls.push(`verify:${email}`); return 'owner'; },
    async removeAvatar(id) { calls.push(`avatar:${id}`); },
    async removeUser(id) { calls.push(`user:${id}`); },
  };
  return { backend, calls };
}
Deno.test('deletes only the authenticated and password-verified account, storage first', async () => {
  const { backend, calls } = fixture();
  assert((await deleteAccount('token', 'password', backend)).status === 200);
  assert(calls.join(',') === 'identify:token,verify:owner@example.com,avatar:owner,user:owner');
});
Deno.test('invalid session cannot reach password verification or deletion', async () => {
  const { backend, calls } = fixture(); backend.identify = async () => null;
  assert((await deleteAccount('token', 'password', backend)).status === 401);
  assert(calls.length === 0);
});
for (const verified of [null, 'another-user']) {
  Deno.test(`wrong password or identity (${verified}) cannot delete`, async () => {
    const { backend, calls } = fixture(); backend.verify = async () => verified;
    assert((await deleteAccount('token', 'password', backend)).status === 403);
    assert(calls.length === 1);
  });
}
Deno.test('storage failure preserves auth account and is retryable', async () => {
  const { backend, calls } = fixture();
  backend.removeAvatar = async () => { throw new Error('offline'); };
  let failed = false;
  try { await deleteAccount('token', 'password', backend); } catch { failed = true; }
  assert(failed); assert(!calls.includes('user:owner'));
  backend.removeAvatar = async () => {};
  assert((await deleteAccount('token', 'password', backend)).status === 200);
});
Deno.test('auth deletion failure never reports success', async () => {
  const { backend } = fixture(); backend.removeUser = async () => { throw new Error('database failed'); };
  let failed = false;
  try { await deleteAccount('token', 'password', backend); } catch { failed = true; }
  assert(failed);
});
