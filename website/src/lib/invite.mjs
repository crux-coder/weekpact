// No arbitrary redirect destinations: only a fixed, registered app scheme.
export function parseInviteUrl(input) {
  let url;
  try { url = new URL(input); } catch { return { kind: 'invalid' }; }
  const values = url.searchParams.getAll('invite');
  if (!values.length) return { kind: 'missing' };
  if (values.length !== 1 || !/^[a-f0-9]{64}$/.test(values[0])) return { kind: 'invalid' };
  return { kind: 'valid', token: values[0] };
}

export function appLink(token) {
  const url = new URL('weekpact://invite');
  if (token !== undefined) {
    if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('Invalid invitation token');
    url.searchParams.set('invite', token);
  }
  return url.href;
}
