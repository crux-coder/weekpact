// Run only against the backend intended for App Review. Credentials are read
// from the environment and never printed. No real user data is copied.
const { SUPABASE_URL: base, SUPABASE_SERVICE_ROLE_KEY: key, REVIEW_EMAIL: email, REVIEW_PASSWORD: password } = process.env;
if (!base || !key || !email || !password || password.length < 12) {
  throw new Error('Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, REVIEW_EMAIL and REVIEW_PASSWORD (at least 12 characters).');
}
const url = new URL(base);
if (url.protocol !== 'https:' && !['127.0.0.1', 'localhost'].includes(url.hostname)) throw new Error('Use HTTPS outside localhost.');
async function api(path, method, body) {
  const response = await fetch(new URL(path, url), {
    method, headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`Review setup request failed (${response.status}, ${method} ${path}). Check the backend configuration; no credentials were logged.`);
  return response.status === 204 ? null : response.json();
}
// Creating a new dedicated email avoids modifying any existing account.
const user = await api('/auth/v1/admin/users', 'POST', {
  email, password, email_confirm: true,
  user_metadata: { first_name: 'App Reviewer', onboarding_completed: true },
});
try {
  const [crew] = await api('/rest/v1/crews', 'POST', { name: 'Review Crew', timezone: 'UTC', owner_id: user.id });
  const goals = await api('/rest/v1/crew_goals', 'POST', [
    { crew_id: crew.id, created_by: user.id, title: 'Take a short walk', frequency: 'daily', days_per_week: 7, icon_key: 'run' },
    { crew_id: crew.id, created_by: user.id, title: 'Read a chapter', frequency: 'weekly', days_per_week: 3, icon_key: 'book' },
  ]);
  await api('/rest/v1/goal_check_ins', 'POST', { goal_id: goals[0].id, user_id: user.id, completed_on: new Date().toISOString().slice(0,10) });
  console.log('Dedicated review account created, email confirmed, with a sample crew, goals and check-in. Add your chosen credentials to App Store Connect Review Information.');
} catch (error) {
  // This invocation created the account, so rollback cannot delete an existing user.
  try { await api(`/auth/v1/admin/users/${user.id}`, 'DELETE'); }
  catch { throw new Error('Review setup failed and rollback could not finish. Remove the newly created review account in Supabase before retrying.'); }
  throw error;
}
