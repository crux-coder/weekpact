import assert from 'node:assert/strict';
import test from 'node:test';
import { appLink, parseInviteUrl } from '../src/lib/invite.mjs';
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
