import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createTestDatabase } from './database_test_schema.mjs';

const migration = '20260914113617_rename_goals_to_pacts.sql';
const db = await createTestDatabase({ beforeMigration: migration });
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [actor, member, crew, pact, session] = [1, 2, 10, 20, 30].map(id);
await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'owner@example.com',now()),($2,'member@example.com',now())", [actor, member]);
await db.query("insert into crews(id,name,owner_id) values($1,'Original crew',$2)", [crew, actor]);
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'member@example.com','member')", [crew, member]);
// The migration must preserve user-authored text, even if it contains the former term.
await db.query("insert into crew_goals(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'My goal stays named by me','weekly',3,$3)", [pact, crew, actor]);
await db.query('insert into auth.sessions(id,user_id) values($1,$2)', [session, member]);
await db.query("insert into private.push_devices(user_id,session_id,token,platform) values($1,$2,repeat('x',30),'ios')", [member, session]);
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [actor]);
await db.query('select save_goal_check_ins($1,current_date,$2)', [crew, [pact]]);
const rows = async table => (await db.query(`select * from ${table}`)).rows;
const before = {
  pacts: await rows('crew_goals'), checks: await rows('goal_check_ins'),
  events: await rows('private.notification_events'), deliveries: await rows('private.notification_deliveries'),
  snapshot: (await db.query('select crew_week_snapshot($1) as data', [crew])).rows[0].data,
};
assert.equal(before.deliveries.length, 1);
await db.exec('begin');
await db.exec(await readFile(new URL('../supabase/migrations/' + migration, import.meta.url), 'utf8'));
await db.exec('commit');
assert.deepEqual(await rows('crew_pacts'), before.pacts);
assert.deepEqual(await rows('pact_check_ins'), before.checks.map(({ goal_id, ...rest }) => ({ ...rest, pact_id: goal_id })));
assert.deepEqual(await rows('private.notification_deliveries'), before.deliveries);
const events = await rows('private.notification_events');
assert.deepEqual(events, before.events.map(event => {
  const { goal_id, goal_title, ...rest } = event.payload;
  return { ...event, type: 'pact_completed', dedupe_key: event.dedupe_key.replace(/^goal_completed:/, 'pact_completed:'),
    payload: { ...rest, pact_id: goal_id, pact_title: goal_title } };
}));
const snapshot = (await db.query('select crew_week_snapshot($1) as data', [crew])).rows[0].data;
const { goals, check_ins, ...rest } = before.snapshot;
assert.deepEqual(snapshot, { ...rest, pacts: goals, check_ins: check_ins.map(({goal_id, ...check}) => ({...check, pact_id: goal_id})) });
await db.query('select save_pact_check_ins($1,current_date,$2)', [crew, []]);
await db.query('select save_pact_check_ins($1,current_date,$2)', [crew, [pact]]);
assert.equal((await rows('private.notification_events')).length, 1, 'rechecking after migration must not duplicate notifications');
assert.equal((await rows('private.notification_deliveries')).length, 1);
assert.equal((await db.query("select to_regclass('public.crew_goals') as name")).rows[0].name, null);
assert.equal((await db.query("select to_regprocedure('public.save_goal_check_ins(uuid,date,uuid[])') as name")).rows[0].name, null);
assert.equal((await db.query("select count(*)::int as count from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and (p.proname ilike '%goal%' or p.prosrc ilike '%goal%')")).rows[0].count, 0);
assert.equal((await db.query("select count(*)::int as count from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relname ilike '%goal%'")).rows[0].count, 0);
assert.equal((await db.query("select bool_and(relrowsecurity) as enabled from pg_class where oid in ('crew_pacts'::regclass,'pact_check_ins'::regclass)")).rows[0].enabled, true);
assert.equal((await db.query("select has_function_privilege('anon','save_pact_check_ins(uuid,date,uuid[])','execute') as allowed")).rows[0].allowed, false);
assert.equal((await db.query("select has_function_privilege('authenticated','save_pact_check_ins(uuid,date,uuid[])','execute') as allowed")).rows[0].allowed, true);
console.log('Pact migration preserved records, IDs, user text, progress, notifications, deduplication, and access controls; old database API names are gone.');
await db.close();
