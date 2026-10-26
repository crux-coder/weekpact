import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `41000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [author, mate, other, outsider] = [1, 2, 3, 4].map(id);
const [crew, foreign] = [11, 12].map(id);
const pact = id(21);
const post = id(31);
const day = '2026-10-26';

for (const user of [author, mate, other, outsider]) {
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
const rpc = (user, sql, params) => asUser(user, async () => (await db.query(sql, params)).rows[0]?.result);
const seeCheckIn = user => rpc(user, 'select mark_check_in_seen($1,$2,$3) as result', [pact, author, day]);
const seePost = user => rpc(user, 'select mark_achievement_seen($1) as result', [post]);
const checkInAudience = user => rpc(user, 'select check_in_audience($1,$2,$3) as result', [pact, author, day]);
const postAudience = user => rpc(user, 'select achievement_audience($1) as result', [post]);
const people = audience => audience.map(({ user_id, clapped }) => ({ user_id, clapped }));

await db.query("update public.users set first_name='Nina' where id=$1", [other]);
await asUser(author, () => db.query('insert into crews(id,name,owner_id) values($1,$2,$3)', [crew, 'Climbers', author]));
await asUser(outsider, () => db.query('insert into crews(id,name,owner_id) values($1,$2,$3)', [foreign, 'Elsewhere', outsider]));
for (const user of [mate, other]) {
  await db.query('insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,$4)', [crew, user, `${user}@example.com`, 'member']);
}
await db.query(
  "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by) values($1,$2,'Climb','weekly',3,'target',$3)",
  [pact, crew, author],
);
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pact, author, day]);
await db.query(
  "insert into crew_achievements(id,crew_id,user_id,body,posted_on,photo_path) values($1,$2,$3,'Sent it',$4,'x.png')",
  [post, crew, author, day],
);

// Nobody has looked yet.
assert.deepEqual(await checkInAudience(author), [], 'a fresh check-in has no audience');

// Crewmates' looks are recorded once each; the poster's own is not a view.
await seeCheckIn(mate);
await seeCheckIn(mate);
await seeCheckIn(author);
await seeCheckIn(other);
assert.equal((await db.query('select count(*)::int as n from check_in_views')).rows[0].n, 2, 'one view per crewmate, none for the poster');
await assert.rejects(seeCheckIn(outsider), /Crew membership required/, 'outsiders cannot mark a view');

// A clap puts its giver first, marked as clapping.
await rpc(other, 'select set_check_in_clap($1,$2,$3,true) as result', [pact, author, day]);
assert.deepEqual(people(await checkInAudience(author)), [
  { user_id: other, clapped: true },
  { user_id: mate, clapped: false },
], 'clappers first, then everyone who only looked');
assert.equal((await checkInAudience(author))[0].display_name, 'Nina', 'named as the crew sees them');
assert.equal((await checkInAudience(author))[1].display_name, 'Crew member');

// A clap given before views were recorded still counts as a look, and a
// self-clap from an older build is left out.
await db.query('delete from check_in_views');
await rpc(author, 'select set_check_in_clap($1,$2,$3,true) as result', [pact, author, day]);
assert.deepEqual(people(await checkInAudience(author)), [{ user_id: other, clapped: true }]);

// Only the poster may read the audience.
await assert.rejects(checkInAudience(mate), /Only the poster/, 'a crewmate cannot read who saw it');
await assert.rejects(postAudience(mate), /Only the poster/);

// Achievements work the same way.
await seePost(mate);
await seePost(author);
await rpc(other, 'select set_achievement_clap($1,true) as result', [post]);
assert.deepEqual(people(await postAudience(author)), [
  { user_id: other, clapped: true },
  { user_id: mate, clapped: false },
]);
await assert.rejects(seePost(outsider), /Crew membership required/);

// No direct read path for anyone signed in.
await assert.rejects(asUser(mate, () => db.query('select * from check_in_views')), /permission denied/);
await assert.rejects(asUser(mate, () => db.query('select * from achievement_views')), /permission denied/);

// Taking a story down takes its views with it.
await db.query('delete from pact_check_ins');
await db.query('delete from crew_achievements');
assert.equal((await db.query('select (select count(*) from check_in_views) + (select count(*) from achievement_views) as n')).rows[0].n, 0);

console.log('story views database tests passed');
