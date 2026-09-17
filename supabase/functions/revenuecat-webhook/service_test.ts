import { handleWebhook, secretMatches, type WebhookBackend } from './service.ts';
function assert(value: unknown, message = 'Assertion failed'): asserts value { if (!value) throw new Error(message); }
const secret = 'shared-secret';
function fixture() {
  const applied: unknown[] = [];
  const backend: WebhookBackend = {
    async apply(payload) { applied.push(payload); return { outcome: 'applied' }; },
  };
  return { backend, applied };
}
const renewal = { event: { id: 'evt', type: 'RENEWAL', app_user_id: 'user', entitlement_ids: ['weekpact_pro'] } };

Deno.test('a correctly signed event reaches the database', async () => {
  const { backend, applied } = fixture();
  const result = await handleWebhook(secret, renewal, secret, backend);
  assert(result.status === 200);
  assert(applied.length === 1 && applied[0] === renewal);
});
for (const provided of [null, '', 'wrong-secret!!', secret + 'x', secret.toUpperCase()]) {
  Deno.test(`a request with ${JSON.stringify(provided)} is rejected and never reaches the database`, async () => {
    const { backend, applied } = fixture();
    const result = await handleWebhook(provided, renewal, secret, backend);
    assert(result.status === 401);
    assert(applied.length === 0);
  });
}
Deno.test('an unconfigured function accepts nothing, not even an empty header', async () => {
  const { backend, applied } = fixture();
  for (const provided of [null, '', 'anything']) {
    assert((await handleWebhook(provided, renewal, '', backend)).status === 503);
  }
  assert(applied.length === 0);
});
for (const body of [null, {}, { event: 'renewal' }, { event: null }]) {
  Deno.test(`a payload without an event object is refused: ${JSON.stringify(body)}`, async () => {
    const { backend, applied } = fixture();
    assert((await handleWebhook(secret, body, secret, backend)).status === 400);
    assert(applied.length === 0);
  });
}
Deno.test('a database failure propagates so RevenueCat retries', async () => {
  const { backend } = fixture();
  backend.apply = () => Promise.reject(new Error('down'));
  let threw = false;
  try { await handleWebhook(secret, renewal, secret, backend); } catch (_) { threw = true; }
  assert(threw);
});
Deno.test('the outcome Postgres reports is passed through, not invented', async () => {
  const { backend } = fixture();
  backend.apply = async () => ({ outcome: 'duplicate' });
  const result = await handleWebhook(secret, renewal, secret, backend);
  assert(result.status === 200 && result.body.outcome === 'duplicate');
});
Deno.test('secret comparison is exact', () => {
  assert(secretMatches(secret, secret));
  assert(!secretMatches(secret.slice(0, -1), secret));
  assert(!secretMatches(' ' + secret, secret));
});
