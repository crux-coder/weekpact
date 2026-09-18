import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `40000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [author, mate, outsider] = [1, 2, 3].map(id);
const [crew, foreign] = [11, 12].map(id);
const [pact, secret] = [21, 22].map(id);
const day = '2026-09-09';

for (const user of [author, mate, outsider]) {
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())', [user, `${user}@example.com`]);
}
async function asUser(user, fn) {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user]);
    await db.exec('set local role authenticated');
    const result = await fn();
    await db.exec('commit');
    return result;
  } catch (e) { await db.exec('rollback'); throw e; }
}
const clap = (user, clapped, target = [pact, author, day]) => asUser(user, async () => (await db.query(
  'select set_check_in_clap($1,$2,$3,$4) as result', [...target, clapped],
)).rows[0].result);
const feed = user => asUser(user, async () =>
  (await db.query('select check_in_feed(null,null,null,null,10) as entries')).rows[0].entries);

await asUser(author, () => db.query('insert into crews(id,name,owner_id) values($1,$2,$3)', [crew, 'Climbers', author]));
await asUser(outsider, () => db.query('insert into crews(id,name,owner_id) values($1,$2,$3)', [foreign, 'Private crew', outsider]));
await db.query('insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,$4)', [crew, mate, `${mate}@example.com`, 'member']);
for (const [pactId, crewId, title, owner] of [[pact, crew, 'Climb twice', author], [secret, foreign, 'Private pact', outsider]]) {
  await db.query(
    "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by) values($1,$2,$3,'weekly',3,'target',$4)",
    [pactId, crewId, title, owner],
  );
}
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on,created_at) values($1,$2,$3,$4)',
  [pact, author, day, `${day}T09:00:00Z`]);
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on,created_at) values($1,$2,$3,$4)',
  [secret, outsider, day, `${day}T10:00:00Z`]);

assert.deepEqual(await clap(mate, true), { clap_count: 1, viewer_clapped: true }, 'a crew mate can clap');
assert.deepEqual(await clap(mate, true), { clap_count: 1, viewer_clapped: true }, 'clapping twice still counts once');
assert.deepEqual(await clap(author, true), { clap_count: 2, viewer_clapped: true }, 'members can clap their own check-in');

const [post] = await feed(mate);
assert.equal(Number(post.clap_count), 2, 'the feed carries the count');
assert.equal(post.viewer_clapped, true, 'and whether the viewer clapped');
assert.equal((await feed(author))[0].viewer_clapped, true);

assert.deepEqual(await clap(mate, false), { clap_count: 1, viewer_clapped: false }, 'unclapping removes only my clap');
assert.deepEqual(await clap(mate, false), { clap_count: 1, viewer_clapped: false }, 'unclapping twice is harmless');
assert.equal((await feed(mate))[0].viewer_clapped, false);

// Only the crews you belong to, in both directions.
await assert.rejects(clap(outsider, true), /Crew membership required/, 'outsiders cannot clap');
await assert.rejects(clap(mate, true, [secret, outsider, day]), /Crew membership required/,
  'members cannot clap a crew they never joined');
await assert.rejects(clap(mate, true, [pact, author, '2026-09-08']), /Crew membership required/,
  'a check-in that does not exist cannot be clapped');
await assert.rejects(
  db.query('select set_check_in_clap($1,$2,$3,true)', [pact, author, day]),
  /Authentication required|permission denied/,
  'unauthenticated callers get nothing',
);
await assert.rejects(
  asUser(mate, () => db.query('insert into check_in_claps(pact_id,check_in_user_id,completed_on,actor_id) values($1,$2,$3,$4)',
    [pact, author, day, mate])),
  /violates row-level security|permission denied/,
  'claps cannot be written around the RPC',
);

// Leaving the crew withdraws the ability to clap, and deleting the check-in
// takes its claps with it.
await db.query('delete from crew_members where crew_id=$1 and user_id=$2', [crew, mate]);
await assert.rejects(clap(mate, true), /Crew membership required/);
await db.query('delete from pact_check_ins where pact_id=$1 and user_id=$2 and completed_on=$3', [pact, author, day]);
assert.equal((await db.query('select count(*)::int as total from check_in_claps')).rows[0].total, 0,
  'claps are removed with the check-in they applaud');

console.log('Check-in clap toggling, crew scope, idempotence, feed counts and cascade passed.');
await db.close();
