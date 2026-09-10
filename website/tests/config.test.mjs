import assert from 'node:assert/strict';
import test from 'node:test';
import { readSiteConfig, appleAssociation, androidAssociation } from '../src/lib/config.mjs';
test('config defaults to the intended domain with no invented download URLs', () => {
  const config = readSiteConfig({});
  assert.equal(config.siteUrl, 'https://weekpact.codepeaktrail.dev');
  assert.equal(config.iosInstallUrl, null);
  assert.equal(config.androidInstallUrl, null);
  assert.deepEqual(androidAssociation(config), []);
  assert.equal(appleAssociation(config).applinks.details[0].appIDs[0], 'R5L8RZTV6R.dev.codepeaktrail.weekpact');
});
test('domain and distribution settings can be changed at build time', () => {
  const fingerprint = Array(32).fill('AB').join(':');
  const config = readSiteConfig({SITE_URL:'https://weekpact.example', PUBLIC_IOS_INSTALL_URL:'https://testflight.apple.com/join/example', ANDROID_SHA256_CERT_FINGERPRINTS:fingerprint});
  assert.equal(config.siteUrl, 'https://weekpact.example');
  assert.equal(androidAssociation(config)[0].target.sha256_cert_fingerprints[0],fingerprint);
});
test('invalid domains, download hosts and certificate formats fail the build', () => {
  for (const SITE_URL of ['http://example.com', 'https://example.com/subpath', 'https://user:pass@example.com', 'https://example.com/?redirect=a']) {
    assert.throws(() => readSiteConfig({SITE_URL}));
  }
  assert.throws(() => readSiteConfig({PUBLIC_IOS_INSTALL_URL:'javascript:alert(1)'}));
  assert.throws(() => readSiteConfig({PUBLIC_IOS_INSTALL_URL:'https://apps.apple.com.evil.example/app'}));
  assert.throws(() => readSiteConfig({ANDROID_SHA256_CERT_FINGERPRINTS:'missing'}));
});
