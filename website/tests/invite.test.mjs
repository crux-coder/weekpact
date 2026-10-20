import assert from 'node:assert/strict';
import test from 'node:test';
import { appLink, codeAppLink, normalizeCode, parseInviteUrl } from '../src/lib/invite.mjs';
const token = 'a'.repeat(64);
test('valid email token reaches only the registered app scheme', () => {
  const state = parseInviteUrl(`https://weekpact.codepeaktrail.dev/invite/?invite=${token}&redirect=https://evil.example`);
  assert.deepEqual(state, {kind: 'valid', token});
  assert.equal(appLink(state.token), `weekpact://invite?invite=${token}`);
});
test('missing token supports the existing in-app inbox', () => {
  assert.deepEqual(parseInviteUrl('https://example.com/invite/'), {kind:'missing'});
  assert.equal(appLink(), 'weekpact://invite');
});
test('rejects truncated, duplicated, encoded markup and malformed token values', () => {
  for (const query of ['invite=', 'invite=short', 'invite=%3Cscript%3E', `invite=${token}&invite=${token}`, `invite=${token}x`, 'invite=%FF']) {
    assert.equal(parseInviteUrl(`https://example.com/invite/?${query}`).kind, 'invalid');
  }
  assert.equal(parseInviteUrl('not a URL').kind, 'invalid');
  assert.throws(() => appLink('javascript:alert(1)'));
});

const from = '0b9c2f4e-6a1d-4e8b-9f3a-2c5d7e8f9a01';
test('crew code links carry the code and inviter to the app scheme only', () => {
  const state = parseInviteUrl(`https://weekpact.codepeaktrail.dev/invite/?code=7K2QXM&from=${from}&redirect=https://evil.example`);
  assert.deepEqual(state, {kind: 'code', code: '7K2QXM', from});
  assert.equal(codeAppLink(state.code, state.from), `weekpact://invite?code=7K2QXM&from=${from}`);
});
test('codes are accepted in any case and normalised to upper case', () => {
  assert.deepEqual(parseInviteUrl('https://example.com/invite/?code=7k2qXm'), {kind: 'code', code: '7K2QXM'});
  assert.equal(normalizeCode('abcdef'), 'ABCDEF');
  assert.equal(codeAppLink('7k2qxm'), 'weekpact://invite?code=7K2QXM');
});
test('the inviter is optional and normalised to lower case', () => {
  assert.deepEqual(parseInviteUrl('https://example.com/invite/?code=7K2QXM'), {kind: 'code', code: '7K2QXM'});
  assert.deepEqual(parseInviteUrl(`https://example.com/invite/?code=7K2QXM&from=${from.toUpperCase()}`), {kind: 'code', code: '7K2QXM', from});
});
test('rejects codes outside the alphabet or of the wrong length', () => {
  // I, L, O, 0 and 1 are left out of the alphabet as look-alikes.
  for (const code of ['', '7K2QX', '7K2QXMM', '7K2QXI', '7K2QXL', '7K2QXO', '7K2QX0', '7K2QX1', '7k2qxl', '7K2-XM', '7K2 XM', '%3Cb%3E1', '7K2QX%C3%84', '7K2Q%C3%9F', '7K2QX%C4%B1', '7K2QX%C5%BF']) {
    assert.equal(parseInviteUrl(`https://example.com/invite/?code=${code}`).kind, 'invalid', code);
    assert.throws(() => codeAppLink(decodeURIComponent(code)));
  }
  assert.equal(parseInviteUrl('https://example.com/invite/?code=7K2QXM&code=7K2QXM').kind, 'invalid');
  assert.equal(normalizeCode(undefined), null);
});
test('rejects a malformed or repeated inviter', () => {
  for (const query of ['from=', 'from=evil', `from=${from}x`, `from=${from.replaceAll('-', '')}`, `from=${from}&from=${from}`]) {
    assert.equal(parseInviteUrl(`https://example.com/invite/?code=7K2QXM&${query}`).kind, 'invalid', query);
  }
  assert.throws(() => codeAppLink('7K2QXM', 'javascript:alert(1)'));
});
test('a link carrying both a code and a legacy token is rejected', () => {
  assert.equal(parseInviteUrl(`https://example.com/invite/?code=7K2QXM&invite=${token}`).kind, 'invalid');
});
test('legacy tokens still parse exactly as before alongside codes', () => {
  assert.deepEqual(parseInviteUrl(`https://example.com/invite/?invite=${token}&from=${from}`), {kind: 'valid', token});
  assert.equal(parseInviteUrl(`https://example.com/invite/?invite=${token.toUpperCase()}`).kind, 'invalid');
});
