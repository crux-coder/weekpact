import { appLink, parseInviteUrl } from '../lib/invite.mjs';

const root = document.querySelector('[data-handoff]');
if (root) {
  const state = parseInviteUrl(location.href);
  const isInvite = root.getAttribute('data-mode') === 'invite';
  const button = document.querySelector('#open-app');
  const heading = document.querySelector('#handoff-title');
  const description = document.querySelector('#handoff-description');
  if (!isInvite && new URL(location.href).searchParams.has('invite')) {
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
    button.setAttribute('href', appLink(state.kind === 'valid' ? state.token : undefined));
    // The app carries the invitation itself: a token arrives with the link and
    // opens the acceptance screen as soon as the account is signed in. There
    // is no inbox to send people to, so the instruction is to come back to the
    // link rather than to go looking for it.
    if (isInvite && state.kind === 'missing') {
      retitle('Find your invitation');
      description.textContent = 'Open the invitation link you were sent, on this device, and tap Open WeekPact. Your invitation opens in the app once you are signed in.';
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
