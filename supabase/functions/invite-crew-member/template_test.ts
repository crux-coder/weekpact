import { renderCrewInvite } from './template.ts';

Deno.test('invitation preserves HTTPS token and explains review and inbox fallback', () => {
  const url = `https://weekpact.codepeaktrail.dev/invite/?invite=${'a'.repeat(64)}`;
  const { html, text } = renderCrewInvite('Early Birds', 'member@example.com', url);
  for (const content of [html, text]) {
    if (!content.includes(url) || !content.includes('Crews → Invites') || !content.includes('accept or decline')) throw new Error('Missing invitation handoff content');
  }
  if (!html.includes('VIEW INVITATION') || !html.includes('Opening this link does not join')) throw new Error('Missing review semantics');
});

Deno.test('invitation escapes dynamic content and link attributes', () => {
  const { html } = renderCrewInvite('<script>alert(1)</script>', 'a&b@example.com', 'https://example.com/?invite=abc&x="bad"');
  if (html.includes('<script>') || !html.includes('a&amp;b@example.com') || !html.includes('&amp;x=&quot;bad&quot;')) throw new Error('Unescaped email content');
});
