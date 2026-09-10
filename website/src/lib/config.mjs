export function readSiteConfig(env = process.env) {
  const url = new URL(env.SITE_URL || 'https://weekpact.codepeaktrail.dev');
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw new Error('SITE_URL must be a bare HTTPS origin, for example https://weekpact.codepeaktrail.dev');
  }
  function installUrl(value, hosts) {
    if (!value?.trim()) return null;
    const link = new URL(value.trim());
    if (link.protocol !== 'https:' || link.username || link.password || !hosts.includes(link.hostname)) {
      throw new Error('Install links must use the official App Store, TestFlight, or Google Play HTTPS host.');
    }
    return link.href;
  }
  const fingerprints = (env.ANDROID_SHA256_CERT_FINGERPRINTS || '').split(',').map(value => value.trim().toUpperCase()).filter(Boolean);
  if (fingerprints.some(value => !/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(value))) {
    throw new Error('Android fingerprints must contain 32 colon-separated hexadecimal bytes.');
  }
  const androidPackage = env.ANDROID_PACKAGE_NAME || 'com.example.keepup';
  if (!/^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$/.test(androidPackage)) throw new Error('Invalid Android package name.');
  const iosAppId = env.IOS_APP_ID || 'R5L8RZTV6R.dev.codepeaktrail.weekpact';
  if (!/^[A-Z0-9]{10}\.[a-zA-Z0-9.-]+$/.test(iosAppId)) throw new Error('Invalid iOS application identifier.');
  return {
    siteUrl: url.origin,
    iosInstallUrl: installUrl(env.PUBLIC_IOS_INSTALL_URL, ['apps.apple.com', 'testflight.apple.com']),
    androidInstallUrl: installUrl(env.PUBLIC_ANDROID_INSTALL_URL, ['play.google.com']),
    iosAppId, androidPackage, fingerprints,
  };
}

export function appleAssociation(config) {
  return { applinks: { details: [{ appIDs: [config.iosAppId], components: [
    { '/': '/invite', comment: 'Email invitation entry point' },
    { '/': '/invite/*' },
    { '/': '/open' },
    { '/': '/open/*' },
  ] }] } };
}

export function androidAssociation(config) {
  return config.fingerprints.length ? [{
    relation: ['delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name: config.androidPackage, sha256_cert_fingerprints: config.fingerprints },
  }] : [];
}
