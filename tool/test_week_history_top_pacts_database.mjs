import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `50000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, mate] = [1, 2].map(id);
const crew = id(11);
const [older, newer] = [21, 22].map(id);

for (const user of [owner, mate]) {
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

await asUser(owner, () => db.query('insert into crews(id,name,owner_id) values($1,$2,$3)', [crew, 'Climbers', owner]));
await db.query('insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,$4)', [crew, mate, `${mate}@example.com`, 'member']);
// A crew from a month ago, so last week is one of its finished weeks.
await db.query("update crews set created_at = now() - interval '30 days' where id = $1", [crew]);
for (const [pact, title, age] of [[older, 'Hangboard', '20 days'], [newer, 'Read', '10 days']]) {
  await db.query(
    `insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by,created_at)
     values($1,$2,$3,'weekly',3,'target',$4,now() - interval '${age}')`,
    [pact, crew, title, owner],
  );
}

// Last week's Monday, in the crew's zone (UTC here).
const monday = (await db.query(
  "select (date_trunc('week', now() at time zone 'UTC')::date - 7)::text as day",
)).rows[0].day;
const plus = async n => (await db.query('select ($1::date + $2::int)::text as day', [monday, n])).rows[0].day;
const keep = async (pact, user, day) => db.query(
  'insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pact, user, day],
);
// Monday: the newer pact twice, the older once — the newer one wins.
await keep(newer, owner, monday);
await keep(newer, mate, monday);
await keep(older, owner, monday);
// Tuesday: one each — a tie goes to the older pact.
await keep(older, mate, await plus(1));
await keep(newer, owner, await plus(1));
// Wednesday onwards: nobody.

const history = await asUser(mate, async () => (await db.query(
  'select crew_week_history($1, null, 1) as result', [crew],
)).rows[0].result);
assert.equal(history.length, 1, 'one finished week');
const [week] = history;
assert.equal(week.week_start, monday);
assert.deepEqual(week.top_pacts, [newer, older, null, null, null, null, null],
  'each day names the pact kept most, the older one on a tie, null on an empty day');
assert.deepEqual(week.days, [1, 1, 0, 0, 0, 0, 0], 'the shares are as before');
assert.ok('percent' in week, 'the existing keys are all still there');

console.log('week history top pacts: ok');
