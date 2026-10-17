// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite entrypoint.
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const existing = '00000000-0000-4000-8000-000000000001';
const fresh = '00000000-0000-4000-8000-000000000002';
const other = '00000000-0000-4000-8000-000000000003';

// An account from before the table existed is carried over with its metadata.
const db = await createTestDatabase({
  beforeMigration: '20261017120000_add_public_users.sql',
});
await db.query(
  'insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',
  [existing, 'old@example.com', { first_name: '  Ada ', last_name: 'Lovelace', avatar_path: `${existing}/avatar.png`, onboarding_completed: true }],
);
const { readFile } = await import('node:fs/promises');
for (const file of ['20261017120000_add_public_users.sql', '20261017130000_add_onboarding_steps.sql']) {
  await db.exec(await readFile(new URL(`../supabase/migrations/${file}`, import.meta.url), 'utf8'));
}
const carried = (await db.query('select * from public.users where id=$1', [existing])).rows[0];
assert.equal(carried.email, 'old@example.com');
assert.equal(carried.first_name, 'Ada');
assert.equal(carried.last_name, 'Lovelace');
assert.equal(carried.avatar_path, `${existing}/avatar.png`);
assert.equal(carried.onboarding_step, 'done');
assert.deepEqual(
  (await db.query('select step from public.user_onboarding_steps where user_id=$1', [existing])).rows,
  [{ step: 'done' }],
);

// A new Auth user gets a row under the same id; onboarding without a name is not done.
await db.query(
  'insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3),($4,$5,$6)',
  [fresh, 'new@example.com', { onboarding_completed: true }, other, 'other@example.com', { first_name: 'Grace' }],
);
const created = (await db.query('select * from public.users where id=$1', [fresh])).rows[0];
assert.equal(created.email, 'new@example.com');
assert.equal(created.first_name, '');
assert.equal(created.onboarding_step, 'profile');
// A name with no onboarding flag is carried, but onboarding is still to do.
assert.deepEqual(
  (await db.query("select first_name,onboarding_step from public.users where id=$1", [other])).rows[0],
  { first_name: 'Grace', onboarding_step: 'profile' },
);

// An email change in Auth follows into the profile.
await db.query("update auth.users set email='moved@example.com' where id=$1", [fresh]);
assert.equal((await db.query('select email from public.users where id=$1', [fresh])).rows[0].email, 'moved@example.com');

async function asUser(user, fn) {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user]);
    await db.exec('set local role authenticated');
    await fn();
  } finally {
    await db.exec('rollback');
  }
}
async function rejects(sql, params) {
  await db.exec('savepoint attempt');
  await assert.rejects(db.query(sql, params));
  await db.exec('rollback to savepoint attempt');
}

await asUser(fresh, async () => {
  // Only your own row is visible or editable.
  assert.deepEqual((await db.query('select id from public.users')).rows.map(r => r.id), [fresh]);
  assert.equal((await db.query("update public.users set first_name='X' where id=$1 returning id", [other])).rows.length, 0);
  // The profile form's fields can be saved together.
  const saved = (await db.query(
    "update public.users set first_name='Grace',last_name='Hopper',avatar_path=$1,onboarding_step='crew' where id=$2 returning *",
    [`${fresh}/avatar.png`, fresh],
  )).rows[0];
  assert.equal(saved.first_name, 'Grace');
  assert.equal(saved.onboarding_step, 'crew');
  // Each step reached is recorded; saving the same step again is not a new one.
  await db.query("update public.users set onboarding_step='done' where id=$1", [fresh]);
  await db.query("update public.users set first_name='Grace' where id=$1", [fresh]);
  // Restarting goes back to the form and keeps the first run's history.
  await db.query("update public.users set onboarding_step='profile' where id=$1", [fresh]);
  assert.deepEqual(
    (await db.query('select step from public.user_onboarding_steps where user_id=$1 order by id', [fresh])).rows.map(r => r.step),
    ['profile', 'crew', 'done', 'profile'],
  );
  // History is read-only, and only your own is visible.
  assert.deepEqual((await db.query('select distinct user_id from public.user_onboarding_steps')).rows.map(r => r.user_id), [fresh]);
  await rejects("insert into public.user_onboarding_steps(user_id,step) values($1,'done')", [fresh]);
  await rejects('delete from public.user_onboarding_steps where user_id=$1', [fresh]);
  // Id and email belong to Auth; avatars must be your own; names are capped.
  await rejects("update public.users set email='x@example.com' where id=$1", [fresh]);
  await rejects('update public.users set avatar_path=$1 where id=$2', [`${other}/avatar.png`, fresh]);
  await rejects("update public.users set first_name=repeat('a',61) where id=$1", [fresh]);
  await rejects("update public.users set first_name='',onboarding_step='crew' where id=$1", [fresh]);
  await rejects("update public.users set onboarding_step='later' where id=$1", [fresh]);
  await rejects("insert into public.users(id,email) values(gen_random_uuid(),'x@example.com')");
  await rejects('delete from public.users where id=$1', [fresh]);
});

// Deleting the Auth user deletes the profile with it.
await db.query('delete from auth.users where id=$1', [fresh]);
assert.equal((await db.query('select count(*)::int as n from public.users where id=$1', [fresh])).rows[0].n, 0);
assert.equal((await db.query('select count(*)::int as n from public.user_onboarding_steps where user_id=$1', [fresh])).rows[0].n, 0);

await db.close();
console.log('Profile creation, carry-over, email sync, onboarding steps and history, own-row access, field limits, and deletion checks passed.');
