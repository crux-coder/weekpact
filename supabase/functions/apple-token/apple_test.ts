import { appleClientSecret, appleConfigFromEnv, exchangeAppleCode, revokeAppleToken, type AppleConfig } from '../_shared/apple.ts';
function assert(value: unknown, message = 'Assertion failed'): asserts value { if (!value) throw new Error(message); }
const decode = (part: string) => Uint8Array.from(atob(part.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
const json = (part: string) => JSON.parse(new TextDecoder().decode(decode(part)));

// A throwaway P-256 key stands in for the .p8 from Apple.
const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----`;
const config: AppleConfig = { teamId: 'TEAM123456', keyId: 'KEY1234567', clientId: 'dev.codepeaktrail.weekpact', privateKey: pem };

function mockFetch(status: number, body: unknown) {
  const calls: { url: string; form: URLSearchParams }[] = [];
  const fetcher = async (url: string, init: RequestInit) => {
    calls.push({ url, form: new URLSearchParams(String(init.body)) });
    return new Response(JSON.stringify(body), { status });
  };
  return { fetcher, calls };
}
async function verifies(secret: string) {
  const [header, claims, signature] = secret.split('.');
  return await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey, decode(signature), new TextEncoder().encode(`${header}.${claims}`));
}

Deno.test('client secret is an ES256 JWT Apple can verify', async () => {
  const now = Date.UTC(2026, 9, 20);
  const secret = await appleClientSecret(config, now);
  const [header, claims] = secret.split('.');
  const h = json(header), c = json(claims);
  assert(h.alg === 'ES256' && h.kid === 'KEY1234567');
  assert(c.iss === 'TEAM123456' && c.sub === 'dev.codepeaktrail.weekpact' && c.aud === 'https://appleid.apple.com');
  assert(c.iat === now / 1000 && c.exp > c.iat && c.exp - c.iat <= 15777000, 'Apple allows at most six months');
  assert(await verifies(secret), 'signature verifies with the public key');
});
Deno.test('keys stored with literal \\n separators still load', async () => {
  const env: Record<string, string> = { APPLE_TEAM_ID: 'T', APPLE_KEY_ID: 'K', APPLE_CLIENT_ID: 'C', APPLE_PRIVATE_KEY: pem.replace(/\n/g, '\\n') };
  const loaded = appleConfigFromEnv(name => env[name])!;
  assert(loaded.privateKey === pem);
  assert(await verifies(await appleClientSecret(loaded)));
  assert(appleConfigFromEnv(name => name === 'APPLE_KEY_ID' ? undefined : env[name]) === null, 'any missing secret disables Apple');
});
Deno.test('exchanges the authorization code for a refresh token', async () => {
  const { fetcher, calls } = mockFetch(200, { access_token: 'a', refresh_token: 'refresh-1', id_token: 'i' });
  assert(await exchangeAppleCode('code-1', config, fetcher) === 'refresh-1');
  assert(calls.length === 1 && calls[0].url === 'https://appleid.apple.com/auth/token');
  const form = calls[0].form;
  assert(form.get('code') === 'code-1' && form.get('grant_type') === 'authorization_code');
  assert(form.get('client_id') === 'dev.codepeaktrail.weekpact');
  assert(await verifies(form.get('client_secret')!));
});
for (const [status, body] of [[400, { error: 'invalid_grant' }], [200, {}], [200, { refresh_token: '' }]] as const) {
  Deno.test(`a refused exchange (${status} ${JSON.stringify(body)}) yields no token`, async () => {
    const { fetcher } = mockFetch(status, body);
    assert(await exchangeAppleCode('code-1', config, fetcher) === null);
  });
}
Deno.test('revokes the refresh token', async () => {
  const { fetcher, calls } = mockFetch(200, {});
  assert(await revokeAppleToken('refresh-1', config, fetcher));
  assert(calls[0].url === 'https://appleid.apple.com/auth/revoke');
  assert(calls[0].form.get('token') === 'refresh-1' && calls[0].form.get('token_type_hint') === 'refresh_token');
  assert(await verifies(calls[0].form.get('client_secret')!));
  assert(!(await revokeAppleToken('refresh-1', config, mockFetch(400, { error: 'invalid_client' }).fetcher)));
});
