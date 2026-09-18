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
    if (isInvite && state.kind === 'missing') {
      retitle('Find your invitation');
      description.textContent = 'Open WeekPact and go to Crews → Invites. Invitations sent to your verified email will be waiting there.';
    } else if (state.kind === 'invalid') {
      retitle('This link looks incomplete');
      description.textContent = 'Try the full link from your invitation email, or open WeekPact and go to Crews → Invites.';
    }
    button.addEventListener('click', () => {
      const feedback = document.querySelector('#open-feedback');
      if (feedback) feedback.removeAttribute('hidden');
    });
  }
}
