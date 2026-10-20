import { appLink, codeAppLink, parseInviteUrl } from '../lib/invite.mjs';

const root = document.querySelector('[data-handoff]');
if (root) {
  const state = parseInviteUrl(location.href);
  const isInvite = root.getAttribute('data-mode') === 'invite';
  const button = document.querySelector('#open-app');
  const heading = document.querySelector('#handoff-title');
  const description = document.querySelector('#handoff-description');
  const params = new URL(location.href).searchParams;
  if (!isInvite && (params.has('invite') || params.has('code'))) {
    location.replace(`/invite/${location.search}`);
  } else if (button && heading && description) {
    // Retitling keeps the wordmark's tinted full stop rather than flattening it.
    const retitle = title => {
      heading.textContent = title;
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.textContent = '.';
      heading.append(dot);
    };
    button.setAttribute('href', state.kind === 'code'
      ? codeAppLink(state.code, state.from)
      : appLink(state.kind === 'valid' ? state.token : undefined));
    // The app carries the invitation itself: a token arrives with the link and
    // opens the acceptance screen as soon as the account is signed in. There
    // is no inbox to send people to, so the instruction is to come back to the
    // link rather than to go looking for it.
    if (isInvite && state.kind === 'missing') {
      retitle('Find your invitation');
      description.textContent = 'Open the invitation link you were sent, on this device, and tap Open WeekPact. Your invitation opens in the app once you are signed in.';
    } else if (isInvite && state.kind === 'code') {
      // The code is the fallback that always works: if the link never reaches
      // the app, typing these six characters in it joins the same crew.
      retitle('You’re invited to a crew');
      description.textContent = 'Join from the WeekPact app with this code. It works until the crew resets it.';
      const panel = document.querySelector('#invite-code');
      const boxes = document.querySelectorAll('#code-boxes .code-box');
      const label = document.querySelector('#open-app-label');
      boxes.forEach((box, i) => { box.textContent = state.code[i]; });
      document.querySelector('#code-boxes')?.setAttribute('aria-label', `Invite code ${state.code.split('').join(' ')}`);
      document.querySelectorAll('[data-code-text]').forEach(node => { node.textContent = state.code; });
      if (label) label.textContent = 'Open in WeekPact';
      const feedback = document.querySelector('#open-feedback');
      if (feedback) feedback.textContent = `If WeekPact didn’t open, install it from the store, then tap Open in WeekPact again — or open the app, tap I have an invite code and type ${state.code}.`;
      panel?.removeAttribute('hidden');
      document.querySelector('#install-help')?.setAttribute('hidden', '');
    } else if (state.kind === 'invalid') {
      retitle('This link looks incomplete');
      description.textContent = 'Tap the full link from the message you were sent. Once the whole link opens the app, your invitation is waiting there.';
    }
    button.addEventListener('click', () => {
      const feedback = document.querySelector('#open-feedback');
      if (feedback) feedback.removeAttribute('hidden');
    });
  }
}
