// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite entrypoint.
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `51000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [me, mate, outsider] = [1, 2, 3].map(id);
const [crew, foreign] = [11, 12].map(id);
const [run, read, elsewhere] = [21, 22, 23].map(id);

for (const user of [me, mate, outsider]) {
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
const rpc = (user, sql, params = []) => asUser(user, async () => (await db.query(sql, params)).rows[0].result);
const mine = user => rpc(user, 'select my_pact_history() as result');
const theirs = (user, target) => rpc(user, 'select member_pact_history($1) as result', [target]);

await asUser(me, () => db.query("insert into crews(id,name,owner_id,timezone) values($1,'Climbers',$2,'UTC')", [crew, me]));
await asUser(outsider, () => db.query("insert into crews(id,name,owner_id) values($1,'Elsewhere',$2)", [foreign, outsider]));
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')", [crew, mate, `${mate}@example.com`]);
await db.query(
  "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by,created_at) values($1,$2,'Run','weekly',3,'run',$3,'2026-09-01'),($4,$2,'Read','daily',7,'book',$3,'2026-09-02')",
  [run, crew, me, read],
);
await db.query(
  "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Far','weekly',1,$3)",
  [elsewhere, foreign, outsider],
);
// Three weeks of Run: the first met, the second one short, the third (long
// ago) met; one day of Read. A crewmate's and an outsider's days are theirs.
const days = [
  ['2026-10-19', run], ['2026-10-21', run], ['2026-10-23', run],
  ['2026-10-12', run], ['2026-10-14', run],
  ['2026-01-05', run], ['2026-01-06', run], ['2026-01-07', run],
  ['2026-10-21', read],
];
for (const [day, pact] of days) {
  await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pact, me, day]);
}
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [run, mate, '2026-10-20']);
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [elsewhere, outsider, '2026-10-20']);

const history = await mine(me);
assert.deepEqual(history.map(p => p.title), ['Run', 'Read'], 'every pact of the crew, in the crew’s order');
const [runHistory, readHistory] = history;
assert.equal(runHistory.crew_name, 'Climbers');
assert.equal(runHistory.pact_index, 0);
assert.equal(readHistory.pact_index, 1);
assert.equal(runHistory.days_per_week, 3);
assert.equal(runHistory.first_day, '2026-01-05');
assert.deepEqual(runHistory.weeks, [
  { start: '2026-01-05', kept: 3 },
  { start: '2026-10-12', kept: 2 },
  { start: '2026-10-19', kept: 3 },
], 'weeks start on Monday and count distinct days');
assert.ok(runHistory.days.every(d => d >= '2026-07-01'), 'the calendar window leaves the old week out');
assert.ok(runHistory.days.includes('2026-10-19') && !runHistory.days.includes('2026-10-20'), 'my days only');
assert.match(runHistory.today, /^\d{4}-\d{2}-\d{2}$/);
assert.equal(readHistory.first_day, '2026-10-21');
assert.deepEqual(readHistory.weeks, [{ start: '2026-10-19', kept: 1 }]);

// A pact never kept still appears, with nothing on it.
const mates = await theirs(me, mate);
assert.deepEqual(mates.map(p => [p.title, p.first_day, p.weeks.length]), [['Run', '2026-10-20', 1], ['Read', null, 0]]);
assert.deepEqual(await theirs(mate, me), history, 'a crewmate reads the same record');

// Nobody outside the crew, in either direction.
await assert.rejects(theirs(outsider, me), /Not a crewmate/);
await assert.rejects(theirs(me, outsider), /Not a crewmate/);
assert.deepEqual((await mine(outsider)).map(p => p.title), ['Far'], 'the outsider sees only their own crew');
await assert.rejects(asUser('', () => db.query('select my_pact_history()')), /Authentication required/);

console.log('pact history database tests passed');
