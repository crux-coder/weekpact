// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite entrypoint.
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';
const db = await createTestDatabase();
const owner = '00000000-0000-4000-8000-000000000001';
const member = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
const crew = '00000000-0000-4000-8000-000000000011';
await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4),($5,$6)', [owner,'owner@example.com',member,'member@example.com',outsider,'outsider@example.com']);
await db.query('insert into public.crews (id,name,owner_id) values ($1,$2,$3)', [crew,'Test Crew',owner]);
await db.query("insert into public.crew_members (crew_id,user_id,email,role) values ($1,$2,'member@example.com','member')", [crew,member]);
let passed = 0;
async function asUser(user, run, role='authenticated') {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub', $1, true)", [user]);
    await db.exec(`set local role ${role}`);
    await run();
  } finally { await db.exec('rollback'); }
  passed++;
}
const insert = (frequency,days,createdBy=owner,title='Walk outside') => db.query('insert into crew_pacts (crew_id,title,frequency,days_per_week,created_by) values ($1,$2,$3,$4,$5) returning id', [crew,title,frequency,days,createdBy]);
await asUser(owner, async () => {
  assert.equal((await insert('daily',7)).rows.length,1);
  assert.equal((await insert('weekly',1)).rows.length,1);
  assert.equal((await insert('weekly',7)).rows.length,1);
});
// Seed one pact as administrator to verify RLS reads independently of inserts.
await insert('daily',7);
await asUser(member, async () => assert.equal((await db.query('select * from crew_pacts')).rows.length,1));
await asUser(outsider, async () => assert.equal((await db.query('select * from crew_pacts')).rows.length,0));
for (const [user,createdBy] of [[member,member],[outsider,outsider],[owner,member]]) {
  await asUser(user, async () => assert.rejects(insert('weekly',3,createdBy), error => error.code === '42501'));
}
for (const [frequency,days,title] of [['daily',3,'Read'],['weekly',0,'Read'],['weekly',8,'Read'],['monthly',3,'Read'],['weekly',3,' '],['weekly',3,'x'.repeat(101)]]) {
  await asUser(owner, async () => assert.rejects(insert(frequency,days,owner,title), error => error.code === '23514'));
}
await asUser('', async () => assert.rejects(db.query('select * from crew_pacts'), error => error.code === '42501'), 'anon');
await asUser(owner, async () => {
  const updated = await db.query("update crew_pacts set title='Changed', frequency='weekly', days_per_week=3, icon_key='book' returning *");
  assert.equal(updated.rows.length, 1);
  assert.equal(updated.rows[0].icon_key, 'book');
  assert.equal(updated.rows[0].days_per_week, 3);
});
for (const user of [member, outsider]) {
  await asUser(user, async () => assert.equal((await db.query("update crew_pacts set title='Changed' returning id")).rows.length, 0));
}
for (const column of ['crew_id', 'created_by', 'id']) {
  await asUser(owner, async () => assert.rejects(db.query(`update crew_pacts set ${column}=$1`, [outsider]), error => error.code === '42501'));
}
await asUser(owner, async () => assert.rejects(db.query("update crew_pacts set days_per_week=3"), error => error.code === '23514'));
await asUser(owner, async () => assert.rejects(db.query('delete from crew_pacts'), error => error.code === '42501'));
const policy = await db.query("select relrowsecurity from pg_class where oid='public.crew_pacts'::regclass");
assert.equal(policy.rows[0].relrowsecurity,true);



await asUser(owner, async () => {
  const result = await db.query("insert into crew_pacts (crew_id,title,frequency,days_per_week,created_by,icon_key) values ($1,'Read','daily',7,$2,'book') returning icon_key", [crew,owner]);
  assert.equal(result.rows[0].icon_key, 'book');
});
await asUser(owner, async () => {
  await assert.rejects(db.query("insert into crew_pacts (crew_id,title,frequency,days_per_week,created_by,icon_key) values ($1,'Read','daily',7,$2,'invalid')", [crew,owner]), /check constraint/);
});


const pactId = (await db.query('select id from crew_pacts limit 1')).rows[0].id;
const today = (await db.query("select to_char(now() at time zone 'UTC', 'YYYY-MM-DD') as day")).rows[0].day;
const save = (ids, day=today, crewId=crew) => db.query('select public.save_pact_check_ins($1,$2,$3::uuid[])', [crewId,day,ids]);
await asUser(member, async () => {
  await save([pactId, pactId]);
  await save([pactId]);
  let snapshot = (await db.query('select public.crew_week_snapshot($1) as data', [crew])).rows[0].data;
  assert.equal(snapshot.today, today);
  assert.equal(snapshot.check_ins.length, 1);
  assert.equal(snapshot.check_ins[0].user_id, member);
  assert.equal(snapshot.members.length, 2);
  await save([]);
  snapshot = (await db.query('select public.crew_week_snapshot($1) as data', [crew])).rows[0].data;
  assert.equal(snapshot.check_ins.length, 0);
});
await asUser(outsider, async () => assert.rejects(save([pactId]), e => e.code === '42501'));
await asUser(outsider, async () => assert.rejects(db.query('select public.crew_week_snapshot($1)', [crew]), e => e.code === '42501'));
await asUser(member, async () => assert.rejects(save([outsider]), e => e.code === '22023'));
await asUser(member, async () => assert.rejects(save([pactId], '2000-01-01'), e => e.code === '22023'));
await asUser(member, async () => assert.rejects(save([pactId], '2099-01-01'), e => e.code === '22023'));
await asUser(member, async () => assert.rejects(db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pactId,owner,today]), e => e.code === '42501'));
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pactId,owner,today]);
await asUser(member, async () => {
  await save([]);
  const snapshot = (await db.query('select public.crew_week_snapshot($1) as data', [crew])).rows[0].data;
  assert.equal(snapshot.check_ins.length, 1);
  assert.equal(snapshot.check_ins[0].user_id, owner);
});
await asUser(outsider, async () => assert.equal((await db.query('select * from pact_check_ins')).rows.length, 0));
await asUser('', async () => assert.rejects(save([pactId]), e => e.code === '42501'), 'anon');
const otherCrew = '00000000-0000-4000-8000-000000000012';
await db.query("insert into crews(id,name,owner_id) values($1,'Other Crew',$2)", [otherCrew,outsider]);
const otherPact = (await db.query("insert into crew_pacts(crew_id,title,frequency,days_per_week,created_by) values($1,'Other pact','daily',7,$2) returning id", [otherCrew,outsider])).rows[0].id;
await asUser(member, async () => assert.rejects(save([otherPact]), e => e.code === '22023'));
await db.query("update crews set timezone='Pacific/Kiritimati' where id=$1", [crew]);
await asUser(member, async () => {
  const snapshot = (await db.query('select public.crew_week_snapshot($1) as data', [crew])).rows[0].data;
  const expected = (await db.query("select to_char(now() at time zone 'Pacific/Kiritimati','YYYY-MM-DD') as day, to_char(date_trunc('week', now() at time zone 'Pacific/Kiritimati'),'YYYY-MM-DD') as start")).rows[0];
  assert.equal(snapshot.today, expected.day);
  assert.equal(snapshot.week_start, expected.start);
  await save([pactId], expected.day);
});

// Two complete prior weeks survive an unfinished current week.
await db.query("update crews set timezone='UTC', created_at=now()-interval '28 days' where id=$1", [crew]);
await db.query("update crew_pacts set frequency='weekly', days_per_week=1, created_at=now()-interval '28 days' where crew_id=$1", [crew]);
await db.query("update crew_members set joined_at=now()-interval '28 days' where crew_id=$1", [crew]);
await db.query('delete from pact_check_ins where pact_id=$1', [pactId]);
await db.query("insert into pact_check_ins(pact_id,user_id,completed_on) select $1,m.user_id,date_trunc('week',now() at time zone 'UTC')::date - w.days from crew_members m cross join (values(7),(14)) w(days) where m.crew_id=$2", [pactId,crew]);
// This admin fixture backdates rows. Rebuild its empty snapshots once before
// testing immutable history; clients cannot delete or rebuild these records.
await db.query('delete from private.crew_week_results where crew_id=$1', [crew]);
const streak = async () => (await db.query('select public.crew_weekly_streak($1) as weeks', [crew])).rows[0].weeks;
await asUser(owner, async () => assert.equal(await streak(), 2));
await asUser(member, async () => {
  const snapshot = (await db.query('select public.crew_week_snapshot($1) as data', [crew])).rows[0].data;
  assert.equal(snapshot.streak_weeks, 2);
});
await asUser(outsider, async () => assert.rejects(streak(), e => e.code === '42501'));
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pactId,owner,today]);
await asUser(member, async () => {
  await save([pactId]);
  assert.equal(await streak(), 3);
  await save([]);
  assert.equal(await streak(), 2);
});
await db.query("delete from pact_check_ins where pact_id=$1 and user_id=$2 and completed_on=date_trunc('week',now() at time zone 'UTC')::date-7", [pactId,member]);
await asUser(owner, async () => assert.equal(await streak(), 2));
await asUser(member, async () => {
  await save([pactId]);
  assert.equal(await streak(), 3);
});
console.log(`${passed} PostgreSQL permission and validation scenarios passed; RLS enabled.`);
await db.close();
