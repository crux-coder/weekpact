// No arbitrary redirect destinations: only a fixed, registered app scheme.

// A crew's invite code: six characters with the look-alikes (I, L, O, 0, 1)
// left out, so it survives being read aloud or typed from a screenshot.
// Matched before upper-casing, so a character that upper-cases to two
// (ß → SS) cannot stretch a short value into a code.
const CODE = /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/i;
const TOKEN = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Codes are shown upper case but accepted in any case; the result is the
// canonical form, or null when the value is not a code.
export function normalizeCode(value) {
  if (typeof value !== 'string') return null;
  return CODE.test(value) ? value.toUpperCase() : null;
}

function normalizeUuid(value) {
  const uuid = value.toLowerCase();
  return UUID.test(uuid) ? uuid : null;
}

// `?code=` (with an optional inviter `from`) is the crew's standing link;
// `?invite=` is the older single-use email token and still opens as before.
export function parseInviteUrl(input) {
  let url;
  try { url = new URL(input); } catch { return { kind: 'invalid' }; }
  const codes = url.searchParams.getAll('code');
  const tokens = url.searchParams.getAll('invite');
  if (codes.length && tokens.length) return { kind: 'invalid' };
  if (codes.length) {
    const code = codes.length === 1 ? normalizeCode(codes[0]) : null;
    if (!code) return { kind: 'invalid' };
    const froms = url.searchParams.getAll('from');
    if (!froms.length) return { kind: 'code', code };
    const from = froms.length === 1 ? normalizeUuid(froms[0]) : null;
    return from ? { kind: 'code', code, from } : { kind: 'invalid' };
  }
  if (!tokens.length) return { kind: 'missing' };
  if (tokens.length !== 1 || !TOKEN.test(tokens[0])) return { kind: 'invalid' };
  return { kind: 'valid', token: tokens[0] };
}

export function appLink(token) {
  const url = new URL('weekpact://invite');
  if (token !== undefined) {
    if (!TOKEN.test(token)) throw new Error('Invalid invitation token');
    url.searchParams.set('invite', token);
  }
  return url.href;
}

export function codeAppLink(code, from) {
  const canonical = normalizeCode(code);
  if (!canonical) throw new Error('Invalid invite code');
  const url = new URL('weekpact://invite');
  url.searchParams.set('code', canonical);
  if (from !== undefined) {
    const inviter = typeof from === 'string' ? normalizeUuid(from) : null;
    if (!inviter) throw new Error('Invalid inviter');
    url.searchParams.set('from', inviter);
  }
  return url.href;
}
