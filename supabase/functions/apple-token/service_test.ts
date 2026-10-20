import { storeAppleToken, type AppleTokenBackend } from './service.ts';
function assert(value: unknown, message = 'Assertion failed'): asserts value { if (!value) throw new Error(message); }
function fixture() {
  const calls: string[] = [];
  const backend: AppleTokenBackend = {
    async identify(token) { calls.push(`identify:${token}`); return 'user-1'; },
    async exchange(code) { calls.push(`exchange:${code}`); return 'refresh-1'; },
    async save(id, refresh) { calls.push(`save:${id}:${refresh}`); },
  };
  return { backend, calls };
}
Deno.test('stores the refresh token for the signed-in user', async () => {
  const { backend, calls } = fixture();
  const result = await storeAppleToken('jwt', { authorizationCode: 'code-1' }, backend);
  assert(result.status === 200);
  assert(calls.join(',') === 'identify:jwt,exchange:code-1,save:user-1:refresh-1');
});
for (const payload of [null, {}, { authorizationCode: '' }, { authorizationCode: 42 }, { authorizationCode: 'x'.repeat(4097) }]) {
  Deno.test(`rejects a missing or malformed code (${JSON.stringify(payload)?.slice(0, 40)})`, async () => {
    const { backend, calls } = fixture();
    assert((await storeAppleToken('jwt', payload, backend)).status === 400);
    assert(calls.length === 0);
  });
}
Deno.test('an invalid session never reaches Apple', async () => {
  const { backend, calls } = fixture(); backend.identify = async () => null;
  assert((await storeAppleToken('jwt', { authorizationCode: 'code-1' }, backend)).status === 401);
  assert(calls.length === 0);
});
Deno.test('a refused code stores nothing', async () => {
  const { backend, calls } = fixture(); backend.exchange = async () => null;
  assert((await storeAppleToken('jwt', { authorizationCode: 'code-1' }, backend)).status === 400);
  assert(!calls.some(c => c.startsWith('save:')));
});
Deno.test('a storage failure is not reported as success', async () => {
  const { backend } = fixture(); backend.save = async () => { throw new Error('db down'); };
  let failed = false;
  try { await storeAppleToken('jwt', { authorizationCode: 'code-1' }, backend); } catch { failed = true; }
  assert(failed);
});
